<?php

namespace Tests\Feature;

use App\Services\FirebaseService;
use Mockery;
use Tests\TestCase;

class MidwifeBookingEndpointTest extends TestCase
{
    public function test_verified_midwife_can_list_only_her_server_bookings(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('getBookingsForMidwife')
            ->once()
            ->with('midwife-123')
            ->andReturn([[
                'id' => 'booking-123',
                'patient_id' => 'patient-123',
                'slot_id' => 'slot-123',
                'slot_start_at' => '2026-11-05T10:00:00Z',
                'complaint' => 'Keluhan singkat.',
                'amount' => 75000,
                'status' => 'paid_pending_midwife',
                'payment_id' => 'invoice-123',
                'created_at' => '2026-11-04T04:00:00Z',
            ]]);
        $firebase->shouldReceive('getUserProfile')
            ->once()
            ->with('patient-123')
            ->andReturn(['name' => 'Bunda Pasien']);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/midwife/bookings')
            ->assertOk()
            ->assertJsonPath('data.0.id', 'booking-123')
            ->assertJsonPath('data.0.patient_name', 'Bunda Pasien')
            ->assertJsonPath('data.0.midwife_id', 'midwife-123')
            ->assertJsonPath('data.0.status', 'paid_pending_midwife')
            ->assertJsonPath('data.0.amount', 75000);
    }

    public function test_unverified_midwife_cannot_access_midwife_bookings(): void
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
            ->andReturn(['role' => 'midwife', 'verified' => false]);
        $firebase->shouldNotReceive('getBookingsForMidwife');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/midwife/bookings')
            ->assertForbidden()
            ->assertJsonPath('code', 'forbidden');
    }

    public function test_verified_midwife_can_accept_a_paid_booking(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('acceptBookingForMidwife')
            ->once()
            ->with('booking-123', 'midwife-123')
            ->andReturn('accepted');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/accept')
            ->assertOk()
            ->assertJsonPath('data.id', 'booking-123')
            ->assertJsonPath('data.status', 'confirmed');
    }

    public function test_midwife_cannot_accept_another_midwifes_booking(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('acceptBookingForMidwife')
            ->once()
            ->with('booking-123', 'midwife-123')
            ->andReturn('not_owned');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/accept')
            ->assertNotFound()
            ->assertJsonPath('code', 'booking_not_found');
    }

    public function test_verified_midwife_rejection_requires_manual_refund(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('rejectBookingForMidwife')
            ->once()
            ->with('booking-123', 'midwife-123', 'Jadwal tidak tersedia.')
            ->andReturn('rejected');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/reject', [
                'reason' => 'Jadwal tidak tersedia.',
            ])
            ->assertOk()
            ->assertJsonPath('data.status', 'rejected')
            ->assertJsonPath('data.refund_required', true);
    }

    public function test_verified_midwife_can_start_a_confirmed_booking(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('startConsultationForMidwife')
            ->once()
            ->with('booking-123', 'midwife-123')
            ->andReturn('started');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/start')
            ->assertOk()
            ->assertJsonPath('data.id', 'booking-123')
            ->assertJsonPath('data.status', 'active');
    }

    private function authenticateVerifiedMidwife(): FirebaseService
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
            ->andReturn([
                'role' => 'midwife',
                'verified' => true,
                'name' => 'Bidan Terverifikasi',
            ]);

        return $firebase;
    }
}
