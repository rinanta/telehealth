<?php

namespace Tests\Unit;

use App\Services\FirebaseService;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class FirebaseConsultationResultTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config(['firebase.project_id' => 'test-project']);
    }

    public function test_complete_consultation_closes_booking_and_creates_result_in_one_commit(): void
    {
        $this->travelTo('2026-11-04 05:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'dHgx']),
            '*documents/bookings/booking-123?*' => Http::response($this->document('bookings/booking-123', [
                'patient_id' => ['stringValue' => 'patient-123'],
                'midwife_id' => ['stringValue' => 'midwife-123'],
                'status' => ['stringValue' => 'active'],
                'consultation_started_at' => ['timestampValue' => '2026-11-04T04:00:00Z'],
            ])),
            '*documents/users/patient-123' => Http::response($this->document('users/patient-123', [
                'name' => ['stringValue' => 'Bunda Pasien'],
            ])),
            '*:commit' => Http::response(['writeResults' => []]),
        ]);

        $outcome = $this->firebase()->completeConsultationForMidwife(
            'booking-123',
            'midwife-123',
            'Bidan Terverifikasi',
            [
                'summary' => 'Ringkasan.',
                'advice' => 'Saran.',
                'supplement_note' => null,
                'follow_up' => 'Kontrol.',
            ],
        );

        $this->assertSame('completed', $outcome['result']);
        $this->assertSame('Bunda Pasien', $outcome['consultation_result']['patient_name']);
        $this->assertArrayNotHasKey('supplement_note', $outcome['consultation_result']);

        Http::assertSent(static function (Request $request): bool {
            if (! str_ends_with($request->url(), ':commit')) {
                return false;
            }

            $writes = $request->data()['writes'] ?? [];
            $bookingWrite = $writes[0] ?? [];
            $resultWrite = $writes[1] ?? [];

            return count($writes) === 2
                && str_ends_with($bookingWrite['update']['name'], '/bookings/booking-123')
                && ($bookingWrite['update']['fields']['status']['stringValue'] ?? null) === 'completed'
                && ($bookingWrite['updateMask']['fieldPaths'] ?? null) === ['status', 'consultation_completed_at']
                && str_ends_with($resultWrite['update']['name'], '/consultation_results/booking-123')
                && ($resultWrite['currentDocument']['exists'] ?? null) === false
                && ($resultWrite['update']['fields']['summary']['stringValue'] ?? null) === 'Ringkasan.'
                && ($resultWrite['update']['fields']['saved_by']['stringValue'] ?? null) === 'Bidan Terverifikasi'
                && isset($resultWrite['update']['fields']['completed_at']['timestampValue']);
        });
    }

    public function test_complete_consultation_rejects_a_booking_that_is_not_active(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'dHgx']),
            '*documents/bookings/booking-123?*' => Http::response($this->document('bookings/booking-123', [
                'patient_id' => ['stringValue' => 'patient-123'],
                'midwife_id' => ['stringValue' => 'midwife-123'],
                'status' => ['stringValue' => 'confirmed'],
            ])),
        ]);

        $outcome = $this->firebase()->completeConsultationForMidwife(
            'booking-123',
            'midwife-123',
            'Bidan',
            ['summary' => 'a', 'advice' => 'b', 'follow_up' => 'c'],
        );

        $this->assertSame('not_active', $outcome['result']);
        Http::assertNotSent(static fn (Request $request): bool => str_ends_with($request->url(), ':commit'));
    }

    public function test_complete_consultation_rejects_a_booking_owned_by_another_midwife(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'dHgx']),
            '*documents/bookings/booking-123?*' => Http::response($this->document('bookings/booking-123', [
                'patient_id' => ['stringValue' => 'patient-123'],
                'midwife_id' => ['stringValue' => 'someone-else'],
                'status' => ['stringValue' => 'active'],
            ])),
        ]);

        $outcome = $this->firebase()->completeConsultationForMidwife(
            'booking-123',
            'midwife-123',
            'Bidan',
            ['summary' => 'a', 'advice' => 'b', 'follow_up' => 'c'],
        );

        $this->assertSame('not_owned', $outcome['result']);
    }

    public function test_complete_consultation_reports_a_conflict_when_commit_is_rejected(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'dHgx']),
            '*documents/bookings/booking-123?*' => Http::response($this->document('bookings/booking-123', [
                'patient_id' => ['stringValue' => 'patient-123'],
                'midwife_id' => ['stringValue' => 'midwife-123'],
                'status' => ['stringValue' => 'active'],
            ])),
            '*documents/users/patient-123' => Http::response($this->document('users/patient-123', [
                'name' => ['stringValue' => 'Bunda Pasien'],
            ])),
            '*:commit' => Http::response(['error' => ['status' => 'ALREADY_EXISTS']], 409),
        ]);

        $outcome = $this->firebase()->completeConsultationForMidwife(
            'booking-123',
            'midwife-123',
            'Bidan',
            ['summary' => 'a', 'advice' => 'b', 'follow_up' => 'c'],
        );

        $this->assertSame('conflict', $outcome['result']);
    }

    public function test_get_consultation_result_returns_null_when_missing(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            '*documents/consultation_results/booking-123' => Http::response([], 404),
        ]);

        $this->assertNull($this->firebase()->getConsultationResult('booking-123'));
    }

    public function test_get_consultation_result_decodes_the_stored_document(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            '*documents/consultation_results/booking-123' => Http::response($this->document(
                'consultation_results/booking-123',
                [
                    'summary' => ['stringValue' => 'Ringkasan.'],
                    'completed_at' => ['timestampValue' => '2026-11-04T05:00:00Z'],
                ],
            )),
        ]);

        $result = $this->firebase()->getConsultationResult('booking-123');

        $this->assertSame('booking-123', $result['id']);
        $this->assertSame('Ringkasan.', $result['summary']);
        $this->assertSame('2026-11-04T05:00:00Z', $result['completed_at']);
    }

    /**
     * @param  array<string, mixed>  $fields
     * @return array<string, mixed>
     */
    private function document(string $path, array $fields): array
    {
        return [
            'name' => 'projects/test-project/databases/(default)/documents/'.$path,
            'fields' => $fields,
            'updateTime' => '2026-11-04T04:00:00Z',
        ];
    }

    private function firebase(): FirebaseService
    {
        return new class extends FirebaseService
        {
            protected function firestoreAccessToken(): string
            {
                return 'test-access-token';
            }
        };
    }
}
