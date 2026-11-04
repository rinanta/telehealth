<?php

namespace Tests\Unit;

use App\Exceptions\MayarApiException;
use App\Services\MayarService;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use RuntimeException;
use Tests\TestCase;

class MayarServiceTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'services.mayar.api_key' => 'sandbox-test-key',
            'services.mayar.environment' => 'sandbox',
        ]);
    }

    public function test_create_invoice_sends_the_server_amount_and_hold_expiry(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://api.mayar.club/hl/v2/invoices/create' => Http::response([
                'statusCode' => 200,
                'data' => [
                    'id' => 'invoice-123',
                    'transactionId' => 'transaction-123',
                    'link' => 'https://testingmayar.myr.id/invoices/test',
                ],
            ]),
        ]);

        $invoice = app(MayarService::class)->createInvoice(
            'Bunda',
            'patient@example.com',
            '081234567890',
            75000,
            'booking-123',
            '2026-11-04T04:15:00Z',
        );

        $this->assertSame([
            'id' => 'invoice-123',
            'transaction_id' => 'transaction-123',
            'link' => 'https://testingmayar.myr.id/invoices/test',
        ], $invoice);

        Http::assertSent(static function (Request $request): bool {
            $item = $request->data()['items'][0] ?? [];

            return $request->method() === 'POST'
                && $request->url() === 'https://api.mayar.club/hl/v2/invoices/create'
                && $request->hasHeader('Authorization', 'Bearer sandbox-test-key')
                && ($request->data()['mobile'] ?? null) === '081234567890'
                && ($request->data()['expiredAt'] ?? null) === '2026-11-04T04:15:00Z'
                && ($item['rate'] ?? null) === 75000
                && ($item['quantity'] ?? null) === 1
                && ($request->data()['extraData']['bookingId'] ?? null) === 'booking-123';
        });
    }

    public function test_invoice_detail_uses_the_sandbox_invoice_status_endpoint(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://api.mayar.club/hl/v2/invoices/invoice-123' => Http::response([
                'statusCode' => 200,
                'data' => [
                    'id' => 'invoice-123',
                    'amount' => 75000,
                    'status' => 'paid',
                ],
            ]),
        ]);

        $invoice = app(MayarService::class)->getInvoice('invoice-123');

        $this->assertSame('paid', $invoice['status']);
        $this->assertSame(75000, $invoice['amount']);
        Http::assertSent(static fn (Request $request): bool => $request->method() === 'GET'
            && $request->url() === 'https://api.mayar.club/hl/v2/invoices/invoice-123'
            && $request->hasHeader('Authorization', 'Bearer sandbox-test-key')
        );
    }

    public function test_create_invoice_rejects_non_https_checkout_links(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://api.mayar.club/hl/v2/invoices/create' => Http::response([
                'data' => [
                    'id' => 'invoice-123',
                    'transactionId' => 'transaction-123',
                    'link' => 'http://example.test/pay',
                ],
            ]),
        ]);

        $this->expectException(RuntimeException::class);
        app(MayarService::class)->createInvoice(
            'Bunda',
            'patient@example.com',
            '081234567890',
            75000,
            'booking-123',
            '2026-11-04T04:15:00Z',
        );
    }

    public function test_invoice_creation_preserves_provider_status_without_exposing_response_body(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://api.mayar.club/hl/v2/invoices/create' => Http::response([
                'statusCode' => 401,
                'messages' => 'Unauthorized',
            ], 401),
        ]);

        try {
            app(MayarService::class)->createInvoice(
                'Bunda',
                'patient@example.com',
                '081234567890',
                75000,
                'booking-123',
                '2026-11-04T04:15:00Z',
            );
            $this->fail('A rejected API key should fail invoice creation.');
        } catch (MayarApiException $exception) {
            $this->assertSame('credentials', $exception->failureType);
            $this->assertSame(401, $exception->providerStatus);
            $this->assertSame(
                'Mayar rejected the invoice request.',
                $exception->getMessage(),
            );
        }
    }

    public function test_create_invoice_identifies_tls_handshake_failures(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            'https://api.mayar.club/hl/v2/invoices/create' => static function () {
                throw new ConnectionException(
                    'cURL error 35: OpenSSL SSL_connect: SSL_ERROR_SYSCALL',
                );
            },
        ]);

        try {
            app(MayarService::class)->createInvoice(
                'Bunda',
                'patient@example.com',
                '081234567890',
                75000,
                'booking-123',
                '2026-11-04T04:15:00Z',
            );
            $this->fail('A TLS handshake failure should fail invoice creation.');
        } catch (MayarApiException $exception) {
            $this->assertSame('tls_handshake', $exception->failureType);
        }
    }
}
