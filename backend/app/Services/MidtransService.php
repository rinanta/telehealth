<?php

namespace App\Services;

use App\Exceptions\MidtransApiException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;

class MidtransService
{
    public function isConfigured(): bool
    {
        $serverKey = config('services.midtrans.server_key');

        return is_string($serverKey)
            && $serverKey !== ''
            && in_array(config('services.midtrans.environment'), ['sandbox', 'production'], true);
    }

    /**
     * Creates a Snap payment page. The booking ID doubles as the Midtrans
     * order_id, so a booking can never be charged through two orders.
     *
     * @return array{id: string, transaction_id: string, link: string}
     */
    public function createTransaction(
        string $name,
        string $email,
        string $mobile,
        int $amount,
        string $bookingId,
        string $expiresAt,
    ): array {
        // The payment page must never outlive the slot hold, so round down.
        $secondsLeft = (int) strtotime($expiresAt) - now('UTC')->getTimestamp();
        $durationMinutes = max(1, intdiv($secondsLeft, 60));

        try {
            $response = $this->request()
                ->post($this->snapBaseUrl().'/snap/v1/transactions', [
                    'transaction_details' => [
                        'order_id' => $bookingId,
                        'gross_amount' => $amount,
                    ],
                    'item_details' => [[
                        'id' => 'konsultasi-bidan',
                        'price' => $amount,
                        'quantity' => 1,
                        'name' => 'Konsultasi bidan TeleBunda',
                    ]],
                    'customer_details' => [
                        'first_name' => mb_substr($name, 0, 255),
                        'email' => $email,
                        'phone' => $mobile,
                    ],
                    'expiry' => [
                        'unit' => 'minutes',
                        'duration' => $durationMinutes,
                    ],
                ]);
        } catch (ConnectionException $exception) {
            throw $this->connectionException($exception);
        }

        if (! $response->successful()) {
            throw $this->httpException(
                'Midtrans rejected the transaction request.',
                $response->status(),
            );
        }

        $token = $response->json('token');
        $redirectUrl = $response->json('redirect_url');

        if (
            ! is_string($token) || $token === ''
            || ! is_string($redirectUrl)
            || ! $this->isHttpsUrl($redirectUrl)
        ) {
            throw new MidtransApiException(
                'Midtrans returned an invalid transaction response.',
                'invalid_response',
                $response->status(),
            );
        }

        return [
            'id' => $bookingId,
            'transaction_id' => $token,
            'link' => $redirectUrl,
        ];
    }

    /**
     * Fetches the authoritative transaction status (Midtrans "Get Status" API).
     *
     * `status` is normalised to: paid, pending, expired, failed, refunded or
     * not_found. `amount` is the integer gross amount in IDR.
     *
     * @return array{id: string, status: string, amount: int, transaction_status: string}
     */
    public function getStatus(string $orderId): array
    {
        try {
            $response = $this->request()
                ->get($this->coreBaseUrl().'/v2/'.rawurlencode($orderId).'/status');
        } catch (ConnectionException $exception) {
            throw $this->connectionException($exception);
        }

        // Midtrans reports many errors as HTTP 200 with the real code in the body.
        $bodyStatusCode = (string) $response->json('status_code', '');

        if ($response->status() === 404 || $bodyStatusCode === '404') {
            return [
                'id' => $orderId,
                'status' => 'not_found',
                'amount' => 0,
                'transaction_status' => 'not_found',
            ];
        }

        if (in_array($response->status(), [401, 403], true) || $bodyStatusCode === '401') {
            throw $this->httpException('Midtrans rejected the server key.', 401);
        }

        if (! $response->successful()) {
            throw $this->httpException(
                'Midtrans could not verify the transaction.',
                $response->status(),
            );
        }

        $transactionStatus = $response->json('transaction_status');
        $grossAmount = $response->json('gross_amount');

        if (
            $response->json('order_id') !== $orderId
            || ! is_string($transactionStatus)
            || ! is_numeric($grossAmount)
        ) {
            throw new MidtransApiException(
                'Midtrans returned an invalid transaction status response.',
                'invalid_response',
                $response->status(),
            );
        }

        return [
            'id' => $orderId,
            'status' => $this->normaliseStatus(
                $transactionStatus,
                $response->json('fraud_status'),
            ),
            'amount' => (int) round((float) $grossAmount),
            'transaction_status' => $transactionStatus,
        ];
    }

    /**
     * signature_key = SHA512(order_id + status_code + gross_amount + server_key),
     * built from the raw string values of the notification body.
     */
    public function hasValidNotificationSignature(
        string $orderId,
        string $statusCode,
        string $grossAmount,
        string $signature,
    ): bool {
        $serverKey = config('services.midtrans.server_key');

        if (! is_string($serverKey) || $serverKey === '' || $signature === '') {
            return false;
        }

        return hash_equals(
            hash('sha512', $orderId.$statusCode.$grossAmount.$serverKey),
            strtolower($signature),
        );
    }

    private function normaliseStatus(string $transactionStatus, mixed $fraudStatus): string
    {
        return match ($transactionStatus) {
            'settlement' => 'paid',
            'capture' => $fraudStatus === 'accept' ? 'paid' : 'pending',
            'pending', 'authorize' => 'pending',
            'expire' => 'expired',
            'deny', 'cancel', 'failure' => 'failed',
            'refund', 'partial_refund', 'chargeback', 'partial_chargeback' => 'refunded',
            default => 'pending',
        };
    }

    private function request(): PendingRequest
    {
        $serverKey = config('services.midtrans.server_key');

        if (! is_string($serverKey) || $serverKey === '') {
            throw new MidtransApiException(
                'Midtrans server key is not configured.',
                'configuration',
            );
        }

        // Midtrans uses HTTP Basic auth: the server key is the username and
        // the password stays empty.
        return Http::withBasicAuth($serverKey, '')
            ->acceptJson()
            ->asJson()
            ->connectTimeout(5)
            ->timeout(15);
    }

    private function snapBaseUrl(): string
    {
        return config('services.midtrans.environment') === 'production'
            ? 'https://app.midtrans.com'
            : 'https://app.sandbox.midtrans.com';
    }

    private function coreBaseUrl(): string
    {
        return config('services.midtrans.environment') === 'production'
            ? 'https://api.midtrans.com'
            : 'https://api.sandbox.midtrans.com';
    }

    private function isHttpsUrl(string $url): bool
    {
        $parts = parse_url($url);

        return is_array($parts)
            && ($parts['scheme'] ?? null) === 'https'
            && is_string($parts['host'] ?? null)
            && $parts['host'] !== '';
    }

    private function connectionException(ConnectionException $exception): MidtransApiException
    {
        $failureType = str_contains($exception->getMessage(), 'SSL_ERROR_SYSCALL')
            || str_contains($exception->getMessage(), 'SSL_connect')
            ? 'tls_handshake'
            : 'connection';

        return new MidtransApiException(
            'Midtrans is temporarily unavailable.',
            $failureType,
            previous: $exception,
        );
    }

    private function httpException(string $message, int $status): MidtransApiException
    {
        $failureType = match ($status) {
            401, 403 => 'credentials',
            400, 406 => 'request_rejected',
            429 => 'rate_limited',
            default => 'provider_http_error',
        };

        return new MidtransApiException($message, $failureType, $status);
    }
}
