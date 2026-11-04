<?php

namespace Tests\Feature;

use App\Exceptions\MidtransApiException;
use App\Exceptions\SlotUnavailableException;
use App\Services\FirebaseService;
use App\Services\MidtransService;
use Mockery;
use Mockery\MockInterface;
use Tests\TestCase;

class BookingEndpointTest extends TestCase
{
    public function test_get_booking_requires_a_bearer_token(): void
    {
        $this->getJson('/api/bookings/booking-123')
            ->assertUnauthorized()
            ->assertJsonPath('code', 'unauthenticated');
    }

    public function test_patient_can_read_their_booking(): void
    {
        $firebase = $this->authenticatePatient();
        $firebase->shouldReceive('getBooking')
            ->once()
            ->with('booking-123')
            ->andReturn([
                'id' => 'booking-123',
                'patient_id' => 'patient-123',
                'midwife_id' => 'midwife-123',
                'slot_id' => 'slot-123',
                'slot_start_at' => '2026-11-05T10:00:00Z',
                'amount' => 75000,
                'status' => 'paid_pending_midwife',
                'created_at' => '2026-11-04T04:00:00Z',
                'hold_expires_at' => '2026-11-04T04:15:00Z',
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/bookings/booking-123')
            ->assertOk()
            ->assertJsonPath('data.id', 'booking-123')
            ->assertJsonPath('data.status', 'paid_pending_midwife')
            ->assertJsonPath('data.amount', 75000);
    }

    public function test_patient_cannot_read_another_patients_booking(): void
    {
        $firebase = $this->authenticatePatient();
        $firebase->shouldReceive('getBooking')
            ->once()
            ->with('booking-123')
            ->andReturn([
                'id' => 'booking-123',
                'patient_id' => 'different-patient',
                'status' => 'paid_pending_midwife',
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/bookings/booking-123')
            ->assertNotFound()
            ->assertJsonPath('code', 'booking_not_found');
    }

    public function test_create_booking_requires_a_bearer_token(): void
    {
        $this->postJson('/api/bookings', [
            'slot_id' => 'slot-123',
            'complaint' => 'Keluhan singkat.',
        ])
            ->assertUnauthorized()
            ->assertJsonPath('code', 'unauthenticated');
    }

    public function test_only_patient_profiles_can_create_a_booking(): void
    {
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('isConfigured')->once()->andReturn(true);
        $firebase->shouldReceive('verifyIdToken')
            ->once()
            ->with('valid-token')
            ->andReturn(['sub' => 'midwife-123']);
        $firebase->shouldReceive('getUserProfile')
            ->once()
            ->with('midwife-123')
            ->andReturn(['role' => 'midwife']);
        $firebase->shouldNotReceive('createBookingWithSlotHold');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings', [
                'slot_id' => 'slot-123',
                'complaint' => 'Keluhan singkat.',
            ])
            ->assertForbidden()
            ->assertJsonPath('code', 'forbidden');
    }

    public function test_patient_booking_uses_server_price_and_returns_a_hold(): void
    {
        $firebase = $this->authenticatePatient();
        $firebase->shouldReceive('createBookingWithSlotHold')
            ->once()
            ->with('patient-123', 'slot-123', 'Keluhan singkat.')
            ->andReturn([
                'id' => 'booking-123',
                'patient_id' => 'patient-123',
                'midwife_id' => 'midwife-123',
                'slot_id' => 'slot-123',
                'slot_start_at' => '2026-11-05T10:00:00Z',
                'amount' => 75000,
                'status' => 'awaiting_payment',
                'created_at' => '2026-11-04T04:00:00Z',
                'hold_expires_at' => '2026-11-04T04:15:00Z',
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings', [
                'slot_id' => 'slot-123',
                'complaint' => 'Keluhan singkat.',
                'amount' => 1,
                'patient_id' => 'another-user',
                'status' => 'paid_pending_midwife',
            ])
            ->assertCreated()
            ->assertExactJson([
                'data' => [
                    'id' => 'booking-123',
                    'patient_id' => 'patient-123',
                    'midwife_id' => 'midwife-123',
                    'slot_id' => 'slot-123',
                    'slot_start_at' => '2026-11-05T10:00:00Z',
                    'amount' => 75000,
                    'status' => 'awaiting_payment',
                    'created_at' => '2026-11-04T04:00:00Z',
                    'hold_expires_at' => '2026-11-04T04:15:00Z',
                ],
            ]);
    }

    public function test_create_booking_rejects_missing_slot_and_complaint(): void
    {
        $firebase = $this->authenticatePatient();
        $firebase->shouldNotReceive('createBookingWithSlotHold');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings', [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['slot_id', 'complaint']);
    }

    public function test_create_booking_rejects_a_slot_id_that_contains_a_path_separator(): void
    {
        $firebase = $this->authenticatePatient();
        $firebase->shouldNotReceive('createBookingWithSlotHold');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings', [
                'slot_id' => 'parent/child',
                'complaint' => 'Keluhan singkat.',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['slot_id']);
    }

    public function test_create_booking_returns_conflict_when_another_request_wins_the_slot_race(): void
    {
        $firebase = $this->authenticatePatient();
        $firebase->shouldReceive('createBookingWithSlotHold')
            ->once()
            ->with('patient-123', 'slot-123', 'Keluhan singkat.')
            ->andThrow(new SlotUnavailableException);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings', [
                'slot_id' => 'slot-123',
                'complaint' => 'Keluhan singkat.',
            ])
            ->assertConflict()
            ->assertJsonPath('code', 'slot_unavailable');
    }

    public function test_checkout_creates_a_transaction_using_the_server_booking_amount(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        $holdExpiresAt = now('UTC')->addMinutes(15)->toIso8601String();
        $firebase = $this->authenticatePatient();
        $firebase->shouldReceive('getBooking')
            ->once()
            ->with('booking-123')
            ->andReturn([
                'id' => 'booking-123',
                'patient_id' => 'patient-123',
                'amount' => 75000,
                'status' => 'awaiting_payment',
                'hold_expires_at' => $holdExpiresAt,
            ]);
        $invoice = [
            'id' => 'booking-123',
            'transaction_id' => 'snap-token-123',
            'link' => 'https://app.sandbox.midtrans.com/snap/v4/redirection/snap-token-123',
        ];
        $firebase->shouldReceive('attachPaymentSession')
            ->once()
            ->with('booking-123', 'patient-123', 75000, $holdExpiresAt, $invoice)
            ->andReturn(true);
        $this->app->instance(FirebaseService::class, $firebase);

        $midtrans = Mockery::mock(MidtransService::class);
        $midtrans->shouldReceive('isConfigured')->once()->andReturn(true);
        $midtrans->shouldReceive('createTransaction')
            ->once()
            ->with(
                'Bunda',
                'patient@example.com',
                '081234567890',
                75000,
                'booking-123',
                $holdExpiresAt,
            )
            ->andReturn($invoice);
        $this->app->instance(MidtransService::class, $midtrans);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/checkout', [
                'mobile' => '081234567890',
                'amount' => 1,
            ])
            ->assertCreated()
            ->assertJsonPath('data.payment_id', 'booking-123')
            ->assertJsonPath('data.checkout_url', $invoice['link'])
            ->assertJsonPath('data.status', 'pending');
    }

    public function test_checkout_rejects_an_expired_booking_hold(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        $firebase = $this->authenticatePatient();
        $firebase->shouldReceive('getBooking')
            ->once()
            ->with('booking-123')
            ->andReturn([
                'id' => 'booking-123',
                'patient_id' => 'patient-123',
                'status' => 'awaiting_payment',
                'hold_expires_at' => '2026-11-04T03:59:00Z',
            ]);
        $firebase->shouldNotReceive('attachPaymentSession');
        $this->app->instance(FirebaseService::class, $firebase);

        $midtrans = Mockery::mock(MidtransService::class);
        $midtrans->shouldNotReceive('createTransaction');
        $this->app->instance(MidtransService::class, $midtrans);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/checkout', [
                'mobile' => '081234567890',
            ])
            ->assertConflict()
            ->assertJsonPath('code', 'booking_hold_expired');
    }

    public function test_checkout_reports_invalid_midtrans_server_key_without_exposing_provider_details(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        $holdExpiresAt = now('UTC')->addMinutes(15)->toIso8601String();
        $firebase = $this->authenticatePatient();
        $firebase->shouldReceive('getBooking')
            ->once()
            ->with('booking-123')
            ->andReturn([
                'id' => 'booking-123',
                'patient_id' => 'patient-123',
                'amount' => 75000,
                'status' => 'awaiting_payment',
                'hold_expires_at' => $holdExpiresAt,
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $midtrans = Mockery::mock(MidtransService::class);
        $midtrans->shouldReceive('isConfigured')->once()->andReturn(true);
        $midtrans->shouldReceive('createTransaction')
            ->once()
            ->andThrow(new MidtransApiException(
                'Midtrans rejected the transaction request.',
                'credentials',
                401,
            ));
        $this->app->instance(MidtransService::class, $midtrans);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/checkout', [
                'mobile' => '081234567890',
            ])
            ->assertServiceUnavailable()
            ->assertJsonPath('code', 'payment_auth_failed')
            ->assertJsonPath('provider_status', 401)
            ->assertJsonMissingPath('server_key');
    }

    public function test_checkout_explains_midtrans_tls_handshake_failures(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        $holdExpiresAt = now('UTC')->addMinutes(15)->toIso8601String();
        $firebase = $this->authenticatePatient();
        $firebase->shouldReceive('getBooking')
            ->once()
            ->with('booking-123')
            ->andReturn([
                'id' => 'booking-123',
                'patient_id' => 'patient-123',
                'amount' => 75000,
                'status' => 'awaiting_payment',
                'hold_expires_at' => $holdExpiresAt,
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $midtrans = Mockery::mock(MidtransService::class);
        $midtrans->shouldReceive('isConfigured')->once()->andReturn(true);
        $midtrans->shouldReceive('createTransaction')
            ->once()
            ->andThrow(new MidtransApiException(
                'Midtrans is temporarily unavailable.',
                'tls_handshake',
            ));
        $this->app->instance(MidtransService::class, $midtrans);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/checkout', [
                'mobile' => '081234567890',
            ])
            ->assertStatus(502)
            ->assertJsonPath('code', 'payment_tls_error')
            ->assertJsonPath(
                'message',
                'The backend could not establish a secure HTTPS connection to Midtrans. Check the server network, VPN, proxy, or TLS inspection settings.',
            );
    }

    public function test_midtrans_webhook_verifies_status_with_provider_before_booking_update(): void
    {
        $payload = $this->midtransNotification('booking-123', '200', '75000.00');
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('completePayment')
            ->once()
            ->with('booking-123', [
                'id' => 'booking-123',
                'status' => 'paid',
                'amount' => 75000,
                'transaction_status' => 'settlement',
            ])
            ->andReturn('paid');
        $this->app->instance(FirebaseService::class, $firebase);

        $midtrans = Mockery::mock(MidtransService::class)->makePartial();
        $midtrans->shouldReceive('getStatus')
            ->once()
            ->with('booking-123')
            ->andReturn([
                'id' => 'booking-123',
                'status' => 'paid',
                'amount' => 75000,
                'transaction_status' => 'settlement',
            ]);
        $this->app->instance(MidtransService::class, $midtrans);

        $this->postJson('/api/webhooks/midtrans', $payload)
            ->assertOk()
            ->assertJsonPath('status', 'processed')
            ->assertJsonPath('payments_verified', 1);
    }

    public function test_midtrans_webhook_ignores_orders_that_are_not_paid(): void
    {
        $payload = $this->midtransNotification('booking-123', '201', '75000.00');
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldNotReceive('completePayment');
        $this->app->instance(FirebaseService::class, $firebase);

        $midtrans = Mockery::mock(MidtransService::class)->makePartial();
        $midtrans->shouldReceive('getStatus')
            ->once()
            ->andReturn([
                'id' => 'booking-123',
                'status' => 'pending',
                'amount' => 75000,
                'transaction_status' => 'pending',
            ]);
        $this->app->instance(MidtransService::class, $midtrans);

        $this->postJson('/api/webhooks/midtrans', $payload)
            ->assertOk()
            ->assertJsonPath('status', 'ignored');
    }

    public function test_midtrans_webhook_rejects_an_invalid_signature(): void
    {
        $payload = $this->midtransNotification('booking-123', '200', '75000.00');
        $payload['signature_key'] = str_repeat('0', 128);

        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldNotReceive('completePayment');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->postJson('/api/webhooks/midtrans', $payload)
            ->assertForbidden()
            ->assertJsonPath('code', 'invalid_signature');
    }

    public function test_midtrans_webhook_rejects_a_tampered_amount(): void
    {
        $payload = $this->midtransNotification('booking-123', '200', '75000.00');
        $payload['gross_amount'] = '1000.00';

        $this->postJson('/api/webhooks/midtrans', $payload)
            ->assertForbidden()
            ->assertJsonPath('code', 'invalid_signature');
    }

    public function test_midtrans_webhook_asks_for_a_retry_when_the_provider_is_unreachable(): void
    {
        $payload = $this->midtransNotification('booking-123', '200', '75000.00');
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldNotReceive('completePayment');
        $this->app->instance(FirebaseService::class, $firebase);

        $midtrans = Mockery::mock(MidtransService::class)->makePartial();
        $midtrans->shouldReceive('getStatus')
            ->once()
            ->andThrow(new MidtransApiException('down', 'connection'));
        $this->app->instance(MidtransService::class, $midtrans);

        $this->postJson('/api/webhooks/midtrans', $payload)
            ->assertServiceUnavailable()
            ->assertJsonPath('code', 'payment_unavailable');
    }

    /**
     * @return array<string, string>
     */
    private function midtransNotification(string $orderId, string $statusCode, string $grossAmount): array
    {
        config(['services.midtrans.server_key' => 'SB-Mid-server-test']);

        return [
            'order_id' => $orderId,
            'status_code' => $statusCode,
            'gross_amount' => $grossAmount,
            'transaction_status' => 'settlement',
            'signature_key' => hash(
                'sha512',
                $orderId.$statusCode.$grossAmount.'SB-Mid-server-test',
            ),
        ];
    }

    /**
     * @return MockInterface&FirebaseService
     */
    private function authenticatePatient(): FirebaseService
    {
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('isConfigured')->once()->andReturn(true);
        $firebase->shouldReceive('verifyIdToken')
            ->once()
            ->with('valid-token')
            ->andReturn([
                'sub' => 'patient-123',
                'email' => 'patient@example.com',
            ]);
        $firebase->shouldReceive('getUserProfile')
            ->once()
            ->with('patient-123')
            ->andReturn([
                'role' => 'patient',
                'name' => 'Bunda',
            ]);

        return $firebase;
    }
}
