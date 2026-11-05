<?php

namespace Tests\Feature;

use App\Services\FirebaseService;
use Mockery;
use Tests\TestCase;

class ConsultationResultEndpointTest extends TestCase
{
    public function test_verified_midwife_can_complete_an_active_consultation_with_a_result(): void
    {
        $firebase = $this->authenticate('midwife-123', [
            'role' => 'midwife',
            'verified' => true,
            'name' => 'Bidan Terverifikasi',
        ]);
        $firebase->shouldReceive('completeConsultationForMidwife')
            ->once()
            ->with('booking-123', 'midwife-123', 'Bidan Terverifikasi', [
                'summary' => 'Kram ligamen fisiologis pada trimester dua.',
                'advice' => 'Istirahat miring ke kiri dan peregangan ringan.',
                'supplement_note' => null,
                'follow_up' => 'Kontrol ANC dua minggu lagi.',
            ])
            ->andReturn([
                'result' => 'completed',
                'consultation_completed_at' => '2026-11-04T05:00:00+00:00',
                'consultation_result' => ['id' => 'booking-123'],
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/complete', [
                'summary' => '  Kram ligamen fisiologis pada trimester dua. ',
                'advice' => 'Istirahat miring ke kiri dan peregangan ringan.',
                'supplement_note' => '   ',
                'follow_up' => 'Kontrol ANC dua minggu lagi.',
            ])
            ->assertOk()
            ->assertJsonPath('data.id', 'booking-123')
            ->assertJsonPath('data.status', 'completed')
            ->assertJsonPath('data.consultation_completed_at', '2026-11-04T05:00:00+00:00');
    }

    public function test_midwife_can_save_a_result_with_free_form_optional_sections(): void
    {
        $firebase = $this->authenticate('midwife-123', [
            'role' => 'midwife',
            'verified' => true,
            'name' => 'Bidan Terverifikasi',
        ]);
        $firebase->shouldReceive('completeConsultationForMidwife')
            ->once()
            ->with(
                'booking-123',
                'midwife-123',
                'Bidan Terverifikasi',
                [
                    'summary' => 'pendek',
                    'advice' => '',
                    'supplement_note' => null,
                    'follow_up' => '',
                ],
            )
            ->andReturn([
                'result' => 'completed',
                'consultation_completed_at' => '2026-11-04T05:00:00+00:00',
                'consultation_result' => ['id' => 'booking-123'],
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/complete', ['summary' => 'pendek'])
            ->assertOk()
            ->assertJsonPath('data.status', 'completed');
    }

    public function test_midwife_cannot_complete_a_consultation_that_is_not_active(): void
    {
        $firebase = $this->authenticate('midwife-123', [
            'role' => 'midwife',
            'verified' => true,
            'name' => 'Bidan Terverifikasi',
        ]);
        $firebase->shouldReceive('completeConsultationForMidwife')
            ->once()
            ->andReturn(['result' => 'not_active']);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/complete', $this->resultPayload())
            ->assertConflict()
            ->assertJsonPath('code', 'booking_not_actionable');
    }

    public function test_midwife_cannot_complete_another_midwifes_consultation(): void
    {
        $firebase = $this->authenticate('midwife-123', [
            'role' => 'midwife',
            'verified' => true,
            'name' => 'Bidan Terverifikasi',
        ]);
        $firebase->shouldReceive('completeConsultationForMidwife')
            ->once()
            ->andReturn(['result' => 'not_owned']);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/complete', $this->resultPayload())
            ->assertNotFound()
            ->assertJsonPath('code', 'booking_not_found');
    }

    public function test_patient_cannot_complete_a_consultation(): void
    {
        $firebase = $this->authenticate('patient-123', ['role' => 'patient', 'name' => 'Bunda']);
        $firebase->shouldNotReceive('completeConsultationForMidwife');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/complete', $this->resultPayload())
            ->assertForbidden();
    }

    public function test_patient_can_read_the_result_of_her_completed_booking(): void
    {
        $firebase = $this->authenticate('patient-123', ['role' => 'patient', 'name' => 'Bunda']);
        $firebase->shouldReceive('getBooking')
            ->once()
            ->with('booking-123')
            ->andReturn($this->booking(['status' => 'completed']));
        $firebase->shouldReceive('getConsultationResult')
            ->once()
            ->with('booking-123')
            ->andReturn([
                'id' => 'booking-123',
                'consultation_id' => 'booking-123',
                'patient_name' => 'Bunda',
                'midwife_name' => 'Bidan Terverifikasi',
                'summary' => 'Ringkasan.',
                'advice' => 'Saran.',
                'follow_up' => 'Kontrol.',
                'saved_by' => 'Bidan Terverifikasi',
                'completed_at' => '2026-11-04T05:00:00Z',
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/bookings/booking-123/result')
            ->assertOk()
            ->assertJsonPath('data.booking_id', 'booking-123')
            ->assertJsonPath('data.summary', 'Ringkasan.')
            ->assertJsonPath('data.supplement_note', null)
            ->assertJsonPath('data.saved_by', 'Bidan Terverifikasi')
            ->assertJsonPath('data.completed_at', '2026-11-04T05:00:00Z');
    }

    public function test_result_is_not_available_before_the_booking_is_completed(): void
    {
        $firebase = $this->authenticate('patient-123', ['role' => 'patient', 'name' => 'Bunda']);
        $firebase->shouldReceive('getBooking')
            ->once()
            ->andReturn($this->booking(['status' => 'active']));
        $firebase->shouldNotReceive('getConsultationResult');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/bookings/booking-123/result')
            ->assertNotFound()
            ->assertJsonPath('code', 'result_not_found');
    }

    public function test_other_patient_cannot_read_the_result(): void
    {
        $firebase = $this->authenticate('other-patient-456', ['role' => 'patient', 'name' => 'Lain']);
        $firebase->shouldReceive('getBooking')
            ->once()
            ->andReturn($this->booking(['status' => 'completed']));
        $firebase->shouldNotReceive('getConsultationResult');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/bookings/booking-123/result')
            ->assertNotFound()
            ->assertJsonPath('code', 'booking_not_found');
    }

    public function test_unverified_midwife_cannot_read_the_result(): void
    {
        $firebase = $this->authenticate('midwife-123', [
            'role' => 'midwife',
            'verified' => false,
            'name' => 'Bidan',
        ]);
        $firebase->shouldReceive('getBooking')
            ->once()
            ->andReturn($this->booking(['status' => 'completed']));
        $firebase->shouldNotReceive('getConsultationResult');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/bookings/booking-123/result')
            ->assertNotFound();
    }

    public function test_patient_history_lists_only_her_bookings_without_expired_holds(): void
    {
        $firebase = $this->authenticate('patient-123', ['role' => 'patient', 'name' => 'Bunda']);
        $firebase->shouldReceive('getBookingsForPatient')
            ->once()
            ->with('patient-123')
            ->andReturn([
                $this->booking(['id' => 'old', 'status' => 'completed', 'created_at' => '2026-11-01T04:00:00Z']),
                $this->booking(['id' => 'new', 'status' => 'confirmed', 'created_at' => '2026-11-04T04:00:00Z']),
                $this->booking(['id' => 'gone', 'status' => 'expired', 'created_at' => '2026-11-03T04:00:00Z']),
            ]);
        $firebase->shouldReceive('getUserProfile')
            ->once()
            ->with('midwife-123')
            ->andReturn(['name' => 'Bidan Terverifikasi']);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/history')
            ->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.id', 'new')
            ->assertJsonPath('data.1.id', 'old')
            ->assertJsonPath('data.0.midwife_name', 'Bidan Terverifikasi')
            ->assertJsonPath('data.0.patient_name', 'Bunda');
    }

    public function test_midwife_cannot_use_the_patient_history_endpoint(): void
    {
        $firebase = $this->authenticate('midwife-123', [
            'role' => 'midwife',
            'verified' => true,
            'name' => 'Bidan',
        ]);
        $firebase->shouldNotReceive('getBookingsForPatient');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/history')
            ->assertForbidden();
    }

    /**
     * @return array<string, string>
     */
    private function resultPayload(): array
    {
        return [
            'summary' => 'Kram ligamen fisiologis pada trimester dua.',
            'advice' => 'Istirahat miring ke kiri dan peregangan ringan.',
            'follow_up' => 'Kontrol ANC dua minggu lagi.',
        ];
    }

    /**
     * @param  array<string, mixed>  $overrides
     * @return array<string, mixed>
     */
    private function booking(array $overrides = []): array
    {
        return array_replace([
            'id' => 'booking-123',
            'patient_id' => 'patient-123',
            'midwife_id' => 'midwife-123',
            'slot_id' => 'slot-123',
            'slot_start_at' => '2026-11-04T04:00:00Z',
            'complaint' => 'Pusing.',
            'amount' => 75000,
            'status' => 'completed',
            'created_at' => '2026-11-04T03:00:00Z',
            'consultation_completed_at' => '2026-11-04T05:00:00Z',
        ], $overrides);
    }

    /**
     * @param  array<string, mixed>  $profile
     */
    private function authenticate(string $uid, array $profile): FirebaseService
    {
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('isConfigured')->once()->andReturn(true);
        $firebase->shouldReceive('verifyIdToken')
            ->once()
            ->with('valid-token')
            ->andReturn(['sub' => $uid]);
        $firebase->shouldReceive('getUserProfile')
            ->once()
            ->with($uid)
            ->andReturn($profile);

        return $firebase;
    }
}
