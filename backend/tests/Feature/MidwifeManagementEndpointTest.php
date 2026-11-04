<?php

namespace Tests\Feature;

use App\Services\FirebaseService;
use Mockery;
use Tests\TestCase;

class MidwifeManagementEndpointTest extends TestCase
{
    // ==========================================
    // 1. Profile & Fee Management
    // ==========================================

    public function test_verified_midwife_can_view_her_profile_and_fee(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('getMidwifeProfile')
            ->once()
            ->with('midwife-123')
            ->andReturn([
                'id' => 'midwife-123',
                'display_name' => 'Bidan Siti S.Tr.Keb',
                'credential_label' => 'Bidan Praktik Mandiri',
                'bio' => 'Berpengalaman 10 tahun.',
                'consultation_fee' => 85000,
                'active' => true,
                'verification_status' => 'verified',
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/midwife/profile')
            ->assertOk()
            ->assertJsonPath('data.uid', 'midwife-123')
            ->assertJsonPath('data.display_name', 'Bidan Siti S.Tr.Keb')
            ->assertJsonPath('data.consultation_fee', 85000)
            ->assertJsonPath('data.verification_status', 'verified');
    }

    public function test_unverified_midwife_cannot_access_midwife_profile(): void
    {
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('isConfigured')->once()->andReturn(true);
        $firebase->shouldReceive('verifyIdToken')
            ->once()
            ->with('valid-token')
            ->andReturn(['sub' => 'midwife-unverified']);
        $firebase->shouldReceive('getUserProfile')
            ->once()
            ->with('midwife-unverified')
            ->andReturn(['role' => 'midwife', 'verified' => false]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/midwife/profile')
            ->assertForbidden()
            ->assertJsonPath('code', 'forbidden');
    }

    public function test_patient_cannot_access_midwife_profile(): void
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
            ->andReturn(['role' => 'patient', 'verified' => true]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/midwife/profile')
            ->assertForbidden();
    }

    public function test_verified_midwife_can_update_her_consultation_fee(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('updateMidwifeProfile')
            ->once()
            ->with('midwife-123', ['consultation_fee' => 95000])
            ->andReturn('updated');
        $firebase->shouldReceive('getMidwifeProfile')
            ->once()
            ->with('midwife-123')
            ->andReturn([
                'id' => 'midwife-123',
                'display_name' => 'Bidan Siti',
                'credential_label' => 'BPM',
                'bio' => null,
                'consultation_fee' => 95000,
                'active' => true,
                'verification_status' => 'verified',
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->patchJson('/api/midwife/profile', [
                'consultation_fee' => 95000,
            ])
            ->assertOk()
            ->assertJsonPath('data.consultation_fee', 95000);
    }

    public function test_updating_fee_requires_positive_integer_above_minimum(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->patchJson('/api/midwife/profile', [
                'consultation_fee' => 0,
            ])
            ->assertUnprocessable();
    }

    // ==========================================
    // 2. Slot Management (Jadwal Sendiri)
    // ==========================================

    public function test_verified_midwife_can_list_all_her_slots(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('getSlotsForMidwife')
            ->once()
            ->with('midwife-123')
            ->andReturn([
                [
                    'id' => 'slot-1',
                    'midwife_id' => 'midwife-123',
                    'start_at' => '2026-11-10T09:00:00Z',
                    'end_at' => '2026-11-10T09:30:00Z',
                    'status' => 'available',
                ],
                [
                    'id' => 'slot-2',
                    'midwife_id' => 'midwife-123',
                    'start_at' => '2026-11-10T10:00:00Z',
                    'end_at' => '2026-11-10T10:30:00Z',
                    'status' => 'booked',
                ],
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/midwife/slots')
            ->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.id', 'slot-1')
            ->assertJsonPath('data.0.status', 'available')
            ->assertJsonPath('data.1.id', 'slot-2')
            ->assertJsonPath('data.1.status', 'booked');
    }

    public function test_verified_midwife_can_create_a_new_slot(): void
    {
        $startAt = now()->addDays(2)->setTime(9, 0, 0)->toIso8601String();
        $expectedStart = date('Y-m-d\TH:i:s\Z', strtotime($startAt));
        $expectedEnd = date('Y-m-d\TH:i:s\Z', strtotime($expectedStart) + 1800);

        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('createSlotForMidwife')
            ->once()
            ->with('midwife-123', $expectedStart, $expectedEnd)
            ->andReturn([
                'id' => 'new-slot-uuid',
                'midwife_id' => 'midwife-123',
                'start_at' => $expectedStart,
                'end_at' => $expectedEnd,
                'status' => 'available',
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/midwife/slots', [
                'start_at' => $startAt,
            ])
            ->assertCreated()
            ->assertJsonPath('data.id', 'new-slot-uuid')
            ->assertJsonPath('data.status', 'available');
    }

    public function test_creating_slot_rejects_past_time(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $this->app->instance(FirebaseService::class, $firebase);

        $pastTime = now()->subHour()->toIso8601String();

        $this->withToken('valid-token')
            ->postJson('/api/midwife/slots', [
                'start_at' => $pastTime,
            ])
            ->assertUnprocessable();
    }

    public function test_creating_overlapping_slot_returns_conflict(): void
    {
        $startAt = now()->addDays(2)->setTime(9, 0, 0)->toIso8601String();
        $expectedStart = date('Y-m-d\TH:i:s\Z', strtotime($startAt));
        $expectedEnd = date('Y-m-d\TH:i:s\Z', strtotime($expectedStart) + 1800);

        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('createSlotForMidwife')
            ->once()
            ->with('midwife-123', $expectedStart, $expectedEnd)
            ->andReturn('overlap');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/midwife/slots', [
                'start_at' => $startAt,
            ])
            ->assertStatus(409)
            ->assertJsonPath('code', 'slot_overlap');
    }

    public function test_verified_midwife_can_delete_an_available_slot(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('deleteSlotForMidwife')
            ->once()
            ->with('midwife-123', 'slot-123')
            ->andReturn('deleted');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->deleteJson('/api/midwife/slots/slot-123')
            ->assertOk()
            ->assertJsonPath('data.deleted', true);
    }

    public function test_deleting_booked_or_held_slot_is_rejected(): void
    {
        $firebase = $this->authenticateVerifiedMidwife();
        $firebase->shouldReceive('deleteSlotForMidwife')
            ->once()
            ->with('midwife-123', 'slot-booked')
            ->andReturn('not_available');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->deleteJson('/api/midwife/slots/slot-booked')
            ->assertStatus(409)
            ->assertJsonPath('code', 'slot_not_available');
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
                'name' => 'Bidan Siti',
            ]);

        return $firebase;
    }
}
