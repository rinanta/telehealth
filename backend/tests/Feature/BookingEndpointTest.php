<?php

namespace Tests\Feature;

use App\Exceptions\MayarApiException;
use App\Exceptions\SlotUnavailableException;
use App\Services\FirebaseService;
use App\Services\MayarService;
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

    public function test_checkout_creates_an_invoice_using_the_server_booking_amount(): void
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
            'id' => 'invoice-123',
            'transaction_id' => 'transaction-123',
            'link' => 'https://testingmayar.myr.id/invoices/test',
        ];
        $firebase->shouldReceive('attachMayarInvoice')
            ->once()
            ->with('booking-123', 'patient-123', 75000, $holdExpiresAt, $invoice)
            ->andReturn(true);
        $this->app->instance(FirebaseService::class, $firebase);

        $mayar = Mockery::mock(MayarService::class);
        $mayar->shouldReceive('isConfigured')->once()->andReturn(true);
        $mayar->shouldReceive('createInvoice')
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
        $this->app->instance(MayarService::class, $mayar);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/checkout', [
                'mobile' => '081234567890',
                'amount' => 1,
            ])
            ->assertCreated()
            ->assertJsonPath('data.payment_id', 'invoice-123')
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
        $firebase->shouldNotReceive('attachMayarInvoice');
        $this->app->instance(FirebaseService::class, $firebase);

        $mayar = Mockery::mock(MayarService::class);
        $mayar->shouldNotReceive('createInvoice');
        $this->app->instance(MayarService::class, $mayar);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/checkout', [
                'mobile' => '081234567890',
            ])
            ->assertConflict()
            ->assertJsonPath('code', 'booking_hold_expired');
    }

    public function test_checkout_reports_invalid_mayar_api_key_without_exposing_provider_details(): void
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

        $mayar = Mockery::mock(MayarService::class);
        $mayar->shouldReceive('isConfigured')->once()->andReturn(true);
        $mayar->shouldReceive('createInvoice')
            ->once()
            ->andThrow(new MayarApiException(
                'Mayar rejected the invoice request.',
                'credentials',
                401,
            ));
        $this->app->instance(MayarService::class, $mayar);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/checkout', [
                'mobile' => '081234567890',
            ])
            ->assertServiceUnavailable()
            ->assertJsonPath('code', 'mayar_auth_failed')
            ->assertJsonPath('provider_status', 401)
            ->assertJsonMissingPath('api_key');
    }

    public function test_checkout_explains_mayar_tls_handshake_failures(): void
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

        $mayar = Mockery::mock(MayarService::class);
        $mayar->shouldReceive('isConfigured')->once()->andReturn(true);
        $mayar->shouldReceive('createInvoice')
            ->once()
            ->andThrow(new MayarApiException(
                'Mayar is temporarily unavailable.',
                'tls_handshake',
            ));
        $this->app->instance(MayarService::class, $mayar);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/checkout', [
                'mobile' => '081234567890',
            ])
            ->assertStatus(502)
            ->assertJsonPath('code', 'mayar_tls_error')
            ->assertJsonPath(
                'message',
                'The backend could not establish a secure HTTPS connection to Mayar. Check the server network, VPN, proxy, or TLS inspection settings.',
            );
    }

    public function test_mayar_webhook_verifies_invoice_with_provider_before_booking_update(): void
    {
        config([
            'services.mayar.webhook_secret' => 'test-webhook-secret',
        ]);
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('getPendingMayarPayments')
            ->once()
            ->andReturn([['invoice_id' => 'invoice-123']]);
        $firebase->shouldReceive('completeMayarPayment')
            ->once()
            ->with('invoice-123', [
                'id' => 'invoice-123',
                'amount' => 75000,
                'status' => 'paid',
            ])
            ->andReturn('paid');
        $this->app->instance(FirebaseService::class, $firebase);

        $mayar = Mockery::mock(MayarService::class);
        $mayar->shouldReceive('isConfigured')->once()->andReturn(true);
        $mayar->shouldReceive('getInvoice')
            ->once()
            ->with('invoice-123')
            ->andReturn([
                'id' => 'invoice-123',
                'amount' => 75000,
                'status' => 'paid',
            ]);
        $this->app->instance(MayarService::class, $mayar);

        $this->postJson('/api/webhooks/mayar/test-webhook-secret', [
            'event' => ['received' => 'payment.received'],
            'data' => ['id' => 'webhook-event'],
        ])
            ->assertOk()
            ->assertJsonPath('status', 'processed')
            ->assertJsonPath('payments_verified', 1);
    }

    public function test_mayar_webhook_rejects_an_invalid_url_secret(): void
    {
        config([
            'services.mayar.webhook_secret' => 'test-webhook-secret',
        ]);

        $this->postJson('/api/webhooks/mayar/wrong-secret', [
            'event' => ['received' => 'payment.received'],
        ])->assertNotFound();
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
