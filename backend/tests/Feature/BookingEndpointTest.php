<?php

namespace Tests\Feature;

use App\Exceptions\SlotUnavailableException;
use App\Services\FirebaseService;
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
            ->andReturn(['sub' => 'patient-123']);
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
