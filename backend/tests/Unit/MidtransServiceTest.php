<?php

namespace Tests\Unit;

use App\Exceptions\MidtransApiException;
use App\Services\MidtransService;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use RuntimeException;
use Tests\TestCase;

class MidtransServiceTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'services.midtrans.server_key' => 'SB-Mid-server-test',
            'services.midtrans.environment' => 'sandbox',
        ]);
    }

    public function test_create_transaction_sends_the_server_amount_and_a_hold_bound_expiry(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            'https://app.sandbox.midtrans.com/snap/v1/transactions' => Http::response([
                'token' => 'snap-token-123',
                'redirect_url' => 'https://app.sandbox.midtrans.com/snap/v4/redirection/snap-token-123',
            ], 201),
        ]);

        $payment = app(MidtransService::class)->createTransaction(
            'Bunda',
            'patient@example.com',
            '081234567890',
            75000,
            'booking-123',
            '2026-11-04T04:15:00Z',
        );

        $this->assertSame([
            'id' => 'booking-123',
            'transaction_id' => 'snap-token-123',
            'link' => 'https://app.sandbox.midtrans.com/snap/v4/redirection/snap-token-123',
        ], $payment);

        Http::assertSent(static function (Request $request): bool {
            $data = $request->data();
            $item = $data['item_details'][0] ?? [];

            return $request->method() === 'POST'
                && $request->url() === 'https://app.sandbox.midtrans.com/snap/v1/transactions'
                && $request->hasHeader('Authorization', 'Basic '.base64_encode('SB-Mid-server-test:'))
                && ($data['transaction_details']['order_id'] ?? null) === 'booking-123'
                && ($data['transaction_details']['gross_amount'] ?? null) === 75000
                && ($item['price'] ?? null) === 75000
                && ($item['quantity'] ?? null) === 1
                && ($data['customer_details']['phone'] ?? null) === '081234567890'
                && ($data['expiry']['unit'] ?? null) === 'minutes'
                && ($data['expiry']['duration'] ?? null) === 15;
        });
    }

    public function test_create_transaction_never_asks_for_less_than_one_minute(): void
    {
        $this->travelTo('2026-11-04 04:14:50 UTC');
        Http::preventStrayRequests();
        Http::fake([
            'https://app.sandbox.midtrans.com/snap/v1/transactions' => Http::response([
                'token' => 'snap-token-123',
                'redirect_url' => 'https://app.sandbox.midtrans.com/snap/v4/redirection/snap-token-123',
            ], 201),
        ]);

        app(MidtransService::class)->createTransaction(
            'Bunda',
            'patient@example.com',
            '081234567890',
            75000,
            'booking-123',
            '2026-11-04T04:15:00Z',
        );

        Http::assertSent(static fn (Request $request): bool => ($request->data()['expiry']['duration'] ?? null) === 1);
    }

    public function test_create_transaction_rejects_non_https_payment_links(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://app.sandbox.midtrans.com/snap/v1/transactions' => Http::response([
                'token' => 'snap-token-123',
                'redirect_url' => 'http://example.test/pay',
            ], 201),
        ]);

        $this->expectException(RuntimeException::class);
        app(MidtransService::class)->createTransaction(
            'Bunda',
            'patient@example.com',
            '081234567890',
            75000,
            'booking-123',
            '2026-11-04T04:15:00Z',
        );
    }

    public function test_transaction_creation_preserves_provider_status_without_exposing_response_body(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://app.sandbox.midtrans.com/snap/v1/transactions' => Http::response([
                'error_messages' => ['Access denied due to unauthorized transaction, please check client or server key'],
            ], 401),
        ]);

        try {
            app(MidtransService::class)->createTransaction(
                'Bunda',
                'patient@example.com',
                '081234567890',
                75000,
                'booking-123',
                '2026-11-04T04:15:00Z',
            );
            $this->fail('A rejected server key should fail transaction creation.');
        } catch (MidtransApiException $exception) {
            $this->assertSame('credentials', $exception->failureType);
            $this->assertSame(401, $exception->providerStatus);
            $this->assertSame(
                'Midtrans rejected the transaction request.',
                $exception->getMessage(),
            );
        }
    }

    public function test_create_transaction_identifies_tls_handshake_failures(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://app.sandbox.midtrans.com/snap/v1/transactions' => static function () {
                throw new ConnectionException(
                    'cURL error 35: OpenSSL SSL_connect: SSL_ERROR_SYSCALL',
                );
            },
        ]);

        try {
            app(MidtransService::class)->createTransaction(
                'Bunda',
                'patient@example.com',
                '081234567890',
                75000,
                'booking-123',
                '2026-11-04T04:15:00Z',
            );
            $this->fail('A TLS handshake failure should fail transaction creation.');
        } catch (MidtransApiException $exception) {
            $this->assertSame('tls_handshake', $exception->failureType);
        }
    }

    public function test_status_maps_settlement_to_paid_with_an_integer_amount(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://api.sandbox.midtrans.com/v2/booking-123/status' => Http::response([
                'status_code' => '200',
                'order_id' => 'booking-123',
                'gross_amount' => '75000.00',
                'transaction_status' => 'settlement',
            ]),
        ]);

        $status = app(MidtransService::class)->getStatus('booking-123');

        $this->assertSame('paid', $status['status']);
        $this->assertSame(75000, $status['amount']);
        Http::assertSent(static fn (Request $request): bool => $request->method() === 'GET'
            && $request->url() === 'https://api.sandbox.midtrans.com/v2/booking-123/status'
            && $request->hasHeader('Authorization', 'Basic '.base64_encode('SB-Mid-server-test:'))
        );
    }

    public function test_status_only_treats_accepted_card_captures_as_paid(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://api.sandbox.midtrans.com/v2/booking-123/status' => Http::response([
                'status_code' => '201',
                'order_id' => 'booking-123',
                'gross_amount' => '75000.00',
                'transaction_status' => 'capture',
                'fraud_status' => 'challenge',
            ]),
        ]);

        $this->assertSame('pending', app(MidtransService::class)->getStatus('booking-123')['status']);
    }

    public function test_status_maps_expire_and_deny_to_non_paid_states(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://api.sandbox.midtrans.com/v2/expired-order/status' => Http::response([
                'status_code' => '407',
                'order_id' => 'expired-order',
                'gross_amount' => '75000.00',
                'transaction_status' => 'expire',
            ]),
            'https://api.sandbox.midtrans.com/v2/denied-order/status' => Http::response([
                'status_code' => '202',
                'order_id' => 'denied-order',
                'gross_amount' => '75000.00',
                'transaction_status' => 'deny',
            ]),
        ]);

        $this->assertSame('expired', app(MidtransService::class)->getStatus('expired-order')['status']);
        $this->assertSame('failed', app(MidtransService::class)->getStatus('denied-order')['status']);
    }

    public function test_status_reports_unknown_orders_when_midtrans_answers_404_in_the_body(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://api.sandbox.midtrans.com/v2/booking-123/status' => Http::response([
                'status_code' => '404',
                'status_message' => "Transaction doesn't exist.",
            ]),
        ]);

        $this->assertSame('not_found', app(MidtransService::class)->getStatus('booking-123')['status']);
    }

    public function test_status_rejects_a_response_for_a_different_order(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://api.sandbox.midtrans.com/v2/booking-123/status' => Http::response([
                'status_code' => '200',
                'order_id' => 'someone-elses-order',
                'gross_amount' => '75000.00',
                'transaction_status' => 'settlement',
            ]),
        ]);

        try {
            app(MidtransService::class)->getStatus('booking-123');
            $this->fail('A mismatched order ID must be rejected.');
        } catch (MidtransApiException $exception) {
            $this->assertSame('invalid_response', $exception->failureType);
        }
    }

    public function test_notification_signature_follows_the_documented_sha512_formula(): void
    {
        $signature = hash('sha512', 'booking-123'.'200'.'75000.00'.'SB-Mid-server-test');
        $service = app(MidtransService::class);

        $this->assertTrue($service->hasValidNotificationSignature('booking-123', '200', '75000.00', $signature));
        $this->assertFalse($service->hasValidNotificationSignature('booking-123', '200', '75001.00', $signature));
        $this->assertFalse($service->hasValidNotificationSignature('booking-123', '200', '75000.00', ''));
    }
}
