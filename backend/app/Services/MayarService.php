<?php

namespace App\Services;

use App\Exceptions\MayarApiException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Support\Facades\Http;

class MayarService
{
    public function isConfigured(): bool
    {
        return is_string(config('services.mayar.api_key'))
            && config('services.mayar.api_key') !== ''
            && in_array(config('services.mayar.environment'), ['sandbox', 'production'], true);
    }

    /**
     * @return array{id: string, transaction_id: string, link: string}
     */
    public function createInvoice(
        string $name,
        string $email,
        string $mobile,
        int $amount,
        string $bookingId,
        string $expiresAt,
    ): array {
        try {
            $response = $this->request()
                ->post($this->baseUrl().'/invoices/create', [
                    'name' => $name,
                    'email' => $email,
                    'mobile' => $mobile,
                    'description' => 'Konsultasi TeleBunda '.$bookingId,
                    'expiredAt' => $expiresAt,
                    'items' => [[
                        'quantity' => 1,
                        'rate' => $amount,
                        'description' => 'Konsultasi bidan',
                    ]],
                    'extraData' => ['bookingId' => $bookingId],
                ]);
        } catch (ConnectionException $exception) {
            $failureType = str_contains($exception->getMessage(), 'SSL_ERROR_SYSCALL')
                || str_contains($exception->getMessage(), 'SSL_connect')
                ? 'tls_handshake'
                : 'connection';

            throw new MayarApiException(
                'Mayar is temporarily unavailable.',
                $failureType,
                previous: $exception,
            );
        }

        if (! $response->successful()) {
            throw $this->httpException(
                'Mayar rejected the invoice request.',
                $response->status(),
            );
        }

        $invoice = $response->json('data');

        if (
            ! is_array($invoice)
            || ! is_string($invoice['id'] ?? null)
            || ! is_string($invoice['transactionId'] ?? null)
            || ! is_string($invoice['link'] ?? null)
            || ! $this->isHttpsUrl($invoice['link'])
        ) {
            throw new MayarApiException(
                'Mayar returned an invalid invoice response.',
                'invalid_response',
                $response->status(),
            );
        }

        return [
            'id' => $invoice['id'],
            'transaction_id' => $invoice['transactionId'],
            'link' => $invoice['link'],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function getInvoice(string $invoiceId): array
    {
        try {
            $response = $this->request()
                ->get($this->baseUrl().'/invoices/'.rawurlencode($invoiceId));
        } catch (ConnectionException $exception) {
            throw new MayarApiException(
                'Mayar is temporarily unavailable.',
                'connection',
                previous: $exception,
            );
        }

        if (! $response->successful()) {
            throw $this->httpException(
                'Mayar could not verify the invoice.',
                $response->status(),
            );
        }
        $invoice = $response->json('data');

        if (
            ! is_array($invoice)
            || ! is_string($invoice['id'] ?? null)
            || ! is_string($invoice['status'] ?? null)
            || ! is_numeric($invoice['amount'] ?? null)
        ) {
            throw new MayarApiException(
                'Mayar returned an invalid invoice detail response.',
                'invalid_response',
                $response->status(),
            );
        }

        return $invoice;
    }

    private function request(): PendingRequest
    {
        $apiKey = config('services.mayar.api_key');

        if (! is_string($apiKey) || $apiKey === '') {
            throw new MayarApiException(
                'Mayar API key is not configured.',
                'configuration',
            );
        }

        return Http::withToken($apiKey)
            ->acceptJson()
            ->asJson()
            ->connectTimeout(5)
            ->timeout(15);
    }

    private function baseUrl(): string
    {
        return config('services.mayar.environment') === 'production'
            ? 'https://api.mayar.id/hl/v2'
            : 'https://api.mayar.club/hl/v2';
    }

    private function isHttpsUrl(string $url): bool
    {
        $parts = parse_url($url);

        return is_array($parts)
            && ($parts['scheme'] ?? null) === 'https'
            && is_string($parts['host'] ?? null)
            && $parts['host'] !== '';
    }

    private function httpException(string $message, int $status): MayarApiException
    {
        $failureType = match ($status) {
            401, 403 => 'credentials',
            400 => 'request_rejected',
            429 => 'rate_limited',
            default => 'provider_http_error',
        };

        return new MayarApiException($message, $failureType, $status);
    }
}
