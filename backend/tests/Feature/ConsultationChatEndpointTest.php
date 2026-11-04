<?php

namespace Tests\Feature;

use App\Services\FirebaseService;
use Mockery;
use Tests\TestCase;

class ConsultationChatEndpointTest extends TestCase
{
    public function test_booking_participant_can_read_active_conversation(): void
    {
        $firebase = $this->authenticatedPatient();
        $firebase->shouldReceive('getBooking')
            ->once()
            ->with('booking-123')
            ->andReturn($this->activeBooking());
        $firebase->shouldReceive('getUserProfile')
            ->once()
            ->with('midwife-123')
            ->andReturn(['role' => 'midwife', 'verified' => true, 'name' => 'Bidan']);
        $firebase->shouldReceive('getConsultationMessages')
            ->once()
            ->with('booking-123')
            ->andReturn([[
                'id' => 'message-123',
                'sender_id' => 'midwife-123',
                'sender_name' => 'Bidan',
                'text' => 'Halo.',
                'sent_at' => '2026-11-04T04:05:00Z',
                'is_midwife' => true,
            ]]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/bookings/booking-123/messages')
            ->assertOk()
            ->assertJsonPath('data.booking.id', 'booking-123')
            ->assertJsonPath('data.booking.status', 'active')
            ->assertJsonPath('data.can_send', true)
            ->assertJsonPath('data.messages.0.text', 'Halo.');
    }

    public function test_user_who_is_not_a_booking_participant_cannot_read_chat(): void
    {
        $firebase = $this->authenticatedPatient('other-patient-456');
        $firebase->shouldReceive('getBooking')
            ->once()
            ->with('booking-123')
            ->andReturn($this->activeBooking());
        $firebase->shouldNotReceive('getConsultationMessages');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/bookings/booking-123/messages')
            ->assertNotFound()
            ->assertJsonPath('code', 'booking_not_found');
    }

    public function test_participant_can_send_a_message_during_active_consultation(): void
    {
        $firebase = $this->authenticatedPatient();
        $firebase->shouldReceive('getBooking')
            ->once()
            ->with('booking-123')
            ->andReturn($this->activeBooking());
        $firebase->shouldReceive('getUserProfile')
            ->once()
            ->with('midwife-123')
            ->andReturn(['role' => 'midwife', 'verified' => true, 'name' => 'Bidan']);
        $firebase->shouldReceive('sendConsultationMessage')
            ->once()
            ->with('booking-123', 'patient-123', 'Bunda', 'Halo, Bidan.')
            ->andReturn([
                'result' => 'sent',
                'message' => [
                    'id' => 'message-123',
                    'sender_id' => 'patient-123',
                    'sender_name' => 'Bunda',
                    'text' => 'Halo, Bidan.',
                    'sent_at' => '2026-11-04T04:05:00Z',
                    'is_midwife' => false,
                ],
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/bookings/booking-123/messages', [
                'text' => '  Halo, Bidan.  ',
            ])
            ->assertCreated()
            ->assertJsonPath('data.text', 'Halo, Bidan.')
            ->assertJsonPath('data.is_midwife', false);
    }

    public function test_chat_is_unavailable_before_the_midwife_starts_the_session(): void
    {
        $firebase = $this->authenticatedPatient();
        $firebase->shouldReceive('getBooking')
            ->once()
            ->with('booking-123')
            ->andReturn($this->activeBooking(['status' => 'confirmed']));
        $firebase->shouldReceive('getUserProfile')
            ->once()
            ->with('midwife-123')
            ->andReturn(['role' => 'midwife', 'verified' => true, 'name' => 'Bidan']);
        $firebase->shouldNotReceive('getConsultationMessages');
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/bookings/booking-123/messages')
            ->assertStatus(409)
            ->assertJsonPath('code', 'consultation_not_active');
    }

    /**
     * @param  array<string, mixed>  $overrides
     * @return array<string, mixed>
     */
    private function activeBooking(array $overrides = []): array
    {
        return array_replace([
            'id' => 'booking-123',
            'patient_id' => 'patient-123',
            'midwife_id' => 'midwife-123',
            'slot_id' => 'slot-123',
            'slot_start_at' => '2026-11-04T04:00:00Z',
            'complaint' => 'Pusing.',
            'amount' => 75000,
            'status' => 'active',
            'created_at' => '2026-11-04T04:00:00Z',
            'consultation_started_at' => now('UTC')->subMinute()->toIso8601String(),
        ], $overrides);
    }

    private function authenticatedPatient(string $uid = 'patient-123'): FirebaseService
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
            ->andReturn(['role' => 'patient', 'name' => 'Bunda']);

        return $firebase;
    }
}
