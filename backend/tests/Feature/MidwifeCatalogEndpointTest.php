<?php

namespace Tests\Feature;

use App\Services\FirebaseService;
use Mockery;
use Tests\TestCase;

class MidwifeCatalogEndpointTest extends TestCase
{
    public function test_catalog_requires_a_bearer_token(): void
    {
        $this->getJson('/api/midwives')
            ->assertUnauthorized()
            ->assertJsonPath('code', 'unauthenticated');
    }

    public function test_only_patient_profiles_can_read_the_catalog(): void
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
        $firebase->shouldNotReceive('getActiveVerifiedMidwives');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/midwives')
            ->assertForbidden()
            ->assertJsonPath('code', 'forbidden');
    }

    public function test_catalog_returns_only_public_active_verified_midwives(): void
    {
        $this->authenticatePatient([
            [
                'id' => 'midwife-123',
                'display_name' => 'Bidan Terverifikasi',
                'credential_label' => 'Bidan',
                'bio' => 'Pendampingan kebidanan.',
                'consultation_fee' => 75000,
                'active' => true,
                'verification_status' => 'verified',
                'str_number' => 'must-not-be-exposed',
            ],
            [
                'id' => 'midwife-pending',
                'display_name' => 'Bidan Menunggu',
                'credential_label' => 'Bidan',
                'active' => true,
                'verification_status' => 'pending',
            ],
            [
                'id' => 'midwife-inactive',
                'display_name' => 'Bidan Tidak Aktif',
                'credential_label' => 'Bidan',
                'active' => false,
                'verification_status' => 'verified',
            ],
        ]);

        $this->withToken('valid-token')
            ->getJson('/api/midwives')
            ->assertOk()
            ->assertExactJson([
                'data' => [[
                    'uid' => 'midwife-123',
                    'display_name' => 'Bidan Terverifikasi',
                    'credential_label' => 'Bidan',
                    'bio' => 'Pendampingan kebidanan.',
                    'price' => 75000,
                ]],
            ]);
    }

    public function test_catalog_returns_an_empty_data_list_when_no_eligible_midwives_exist(): void
    {
        $this->authenticatePatient([]);

        $this->withToken('valid-token')
            ->getJson('/api/midwives')
            ->assertOk()
            ->assertExactJson(['data' => []]);
    }

    public function test_slots_only_include_future_available_valid_slots(): void
    {
        $startAt = now()->addHour();
        $endAt = $startAt->copy()->addMinutes(30);
        $validSlot = [
            'id' => 'slot-valid',
            'midwife_id' => 'midwife-123',
            'start_at' => $startAt->toIso8601String(),
            'end_at' => $endAt->toIso8601String(),
            'status' => 'available',
        ];
        $this->authenticatePatient(
            [[
                'id' => 'midwife-123',
                'display_name' => 'Bidan Terverifikasi',
                'credential_label' => 'Bidan',
                'active' => true,
                'verification_status' => 'verified',
            ]],
            [$validSlot, [
                ...$validSlot,
                'id' => 'slot-held',
                'hold_booking_id' => 'booking-123',
            ], [
                ...$validSlot,
                'id' => 'slot-wrong-duration',
                'end_at' => $startAt->copy()->addMinutes(45)->toIso8601String(),
            ], [
                ...$validSlot,
                'id' => 'slot-expired',
                'start_at' => now()->subHour()->toIso8601String(),
                'end_at' => now()->subMinutes(30)->toIso8601String(),
            ]],
        );

        $this->withToken('valid-token')
            ->getJson('/api/midwives/midwife-123/slots')
            ->assertOk()
            ->assertExactJson(['data' => [$validSlot]]);
    }

    public function test_slots_are_not_returned_for_unverified_midwives(): void
    {
        $this->authenticatePatient([[
            'id' => 'midwife-pending',
            'display_name' => 'Bidan Menunggu',
            'credential_label' => 'Bidan',
            'active' => true,
            'verification_status' => 'pending',
        ]]);

        $this->withToken('valid-token')
            ->getJson('/api/midwives/midwife-pending/slots')
            ->assertNotFound()
            ->assertJsonPath('code', 'midwife_not_found');
    }

    /**
     * @param  list<array<string, mixed>>  $midwives
     * @param  list<array<string, mixed>>  $slots
     */
    private function authenticatePatient(array $midwives, array $slots = []): void
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
            ->andReturn(['role' => 'patient']);
        $firebase->shouldReceive('getActiveVerifiedMidwives')->andReturn($midwives);
        if ($slots !== []) {
            $firebase->shouldReceive('getAvailableSlots')
                ->once()
                ->with('midwife-123')
                ->andReturn($slots);
        }
        $this->app->instance(FirebaseService::class, $firebase);
    }
}
