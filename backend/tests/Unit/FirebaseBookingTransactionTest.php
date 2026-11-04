<?php

namespace Tests\Unit;

use App\Exceptions\BookingConfigurationException;
use App\Exceptions\SlotUnavailableException;
use App\Services\FirebaseService;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class FirebaseBookingTransactionTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config(['firebase.project_id' => 'test-project']);
    }

    public function test_get_booking_includes_slot_time_for_older_booking_documents(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            '*documents/bookings/booking-123' => Http::response($this->document(
                'bookings/booking-123',
                [
                    'patient_id' => ['stringValue' => 'patient-123'],
                    'midwife_id' => ['stringValue' => 'midwife-123'],
                    'slot_id' => ['stringValue' => 'slot-123'],
                    'amount' => ['integerValue' => '75000'],
                    'status' => ['stringValue' => 'paid_pending_midwife'],
                    'created_at' => ['timestampValue' => '2026-11-04T04:00:00Z'],
                    'hold_expires_at' => ['timestampValue' => '2026-11-04T04:15:00Z'],
                ],
            )),
            '*documents/slots/slot-123' => Http::response($this->document(
                'slots/slot-123',
                ['start_at' => ['timestampValue' => '2026-11-05T02:00:00Z']],
            )),
        ]);

        $booking = $this->firebase()->getBooking('booking-123');

        $this->assertSame('booking-123', $booking['id']);
        $this->assertSame('paid_pending_midwife', $booking['status']);
        $this->assertSame('2026-11-05T02:00:00Z', $booking['slot_start_at']);
    }

    public function test_create_booking_atomically_holds_the_slot_at_the_trusted_fee(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'dHgx']),
            '*documents/slots/slot-123?*' => Http::response($this->document('slots/slot-123', [
                'midwife_id' => ['stringValue' => 'midwife-123'],
                'start_at' => ['timestampValue' => '2026-11-05T10:00:00Z'],
                'end_at' => ['timestampValue' => '2026-11-05T10:30:00Z'],
                'status' => ['stringValue' => 'available'],
            ])),
            '*documents/midwives/midwife-123?*' => Http::response($this->document('midwives/midwife-123', [
                'display_name' => ['stringValue' => 'Bidan Terverifikasi'],
                'active' => ['booleanValue' => true],
                'verification_status' => ['stringValue' => 'verified'],
                'consultation_fee' => ['integerValue' => '75000'],
            ])),
            '*:commit' => Http::response(['writeResults' => [], 'commitTime' => '2026-11-04T04:00:00Z']),
        ]);

        $booking = $this->firebase()->createBookingWithSlotHold(
            'patient-123',
            'slot-123',
            'Keluhan singkat.',
        );

        $this->assertSame('patient-123', $booking['patient_id']);
        $this->assertSame('midwife-123', $booking['midwife_id']);
        $this->assertSame(75000, $booking['amount']);
        $this->assertSame('awaiting_payment', $booking['status']);
        $this->assertSame('2026-11-04T04:15:00+00:00', $booking['hold_expires_at']);

        Http::assertSent(static function (Request $request): bool {
            if (! str_ends_with($request->url(), ':commit')) {
                return false;
            }

            $writes = $request->data()['writes'] ?? [];
            $slotFields = $writes[0]['update']['fields'] ?? [];
            $bookingFields = $writes[1]['update']['fields'] ?? [];

            return count($writes) === 2
                && ($writes[0]['update']['name'] ?? null)
                    === 'projects/test-project/databases/(default)/documents/slots/slot-123'
                && str_starts_with(
                    $writes[1]['update']['name'] ?? '',
                    'projects/test-project/databases/(default)/documents/bookings/',
                )
                && ($slotFields['status']['stringValue'] ?? null) === 'held'
                && ($slotFields['hold_booking_id']['stringValue'] ?? null)
                    === basename($writes[1]['update']['name'])
                && ($bookingFields['amount']['integerValue'] ?? null) === '75000'
                && ($bookingFields['slot_start_at']['timestampValue'] ?? null)
                    === '2026-11-05T10:00:00Z'
                && ($bookingFields['status']['stringValue'] ?? null) === 'awaiting_payment'
                && ($writes[1]['currentDocument']['exists'] ?? null) === false
                && ($request->data()['transaction'] ?? null) === 'dHgx';
        });
    }

    public function test_create_booking_rejects_a_slot_already_held_by_another_patient(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'dHgx']),
            '*documents/slots/slot-123?*' => Http::response($this->document('slots/slot-123', [
                'midwife_id' => ['stringValue' => 'midwife-123'],
                'status' => ['stringValue' => 'held'],
                'hold_booking_id' => ['stringValue' => 'booking-existing'],
                'hold_expires_at' => ['timestampValue' => '2026-11-04T04:10:00Z'],
            ])),
        ]);

        try {
            $this->firebase()->createBookingWithSlotHold(
                'patient-123',
                'slot-123',
                'Keluhan singkat.',
            );
            $this->fail('A held slot must not be booked again.');
        } catch (SlotUnavailableException) {
            $this->assertTrue(true);
        }

        Http::assertNotSent(
            static fn (Request $request): bool => str_ends_with($request->url(), ':commit'),
        );
    }

    public function test_create_booking_reuses_an_expired_unpaid_hold_atomically(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'dHgx']),
            '*documents/slots/slot-123?*' => Http::response($this->document('slots/slot-123', [
                'midwife_id' => ['stringValue' => 'midwife-123'],
                'start_at' => ['timestampValue' => '2026-11-05T10:00:00Z'],
                'end_at' => ['timestampValue' => '2026-11-05T10:30:00Z'],
                'status' => ['stringValue' => 'held'],
                'hold_booking_id' => ['stringValue' => 'booking-old'],
                'hold_expires_at' => ['timestampValue' => '2026-11-04T03:59:00Z'],
            ])),
            '*documents/bookings/booking-old?*' => Http::response($this->document('bookings/booking-old', [
                'slot_id' => ['stringValue' => 'slot-123'],
                'status' => ['stringValue' => 'awaiting_payment'],
                'payment_id' => ['stringValue' => 'invoice-old'],
                'hold_expires_at' => ['timestampValue' => '2026-11-04T03:59:00Z'],
            ])),
            '*documents/payments/invoice-old?*' => Http::response($this->document(
                'payments/invoice-old',
                ['status' => ['stringValue' => 'pending']],
            )),
            '*documents/midwives/midwife-123?*' => Http::response($this->document('midwives/midwife-123', [
                'active' => ['booleanValue' => true],
                'verification_status' => ['stringValue' => 'verified'],
                'consultation_fee' => ['integerValue' => '75000'],
            ])),
            '*:commit' => Http::response(['writeResults' => [], 'commitTime' => '2026-11-04T04:00:00Z']),
        ]);

        $this->firebase()->createBookingWithSlotHold(
            'patient-123',
            'slot-123',
            'Keluhan singkat.',
        );

        Http::assertSent(static function (Request $request): bool {
            if (! str_ends_with($request->url(), ':commit')) {
                return false;
            }

            $writes = $request->data()['writes'] ?? [];

            return count($writes) === 4
                && ($writes[0]['update']['fields']['status']['stringValue'] ?? null) === 'held'
                && ($writes[1]['update']['fields']['status']['stringValue'] ?? null) === 'expired'
                && ($writes[2]['update']['fields']['status']['stringValue'] ?? null) === 'expired'
                && str_ends_with($writes[2]['update']['name'] ?? '', '/payments/invoice-old')
                && ($writes[3]['update']['fields']['status']['stringValue'] ?? null) === 'awaiting_payment';
        });
    }

    public function test_midwife_without_a_positive_trusted_fee_cannot_be_booked(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'dHgx']),
            '*documents/slots/slot-123?*' => Http::response($this->document('slots/slot-123', [
                'midwife_id' => ['stringValue' => 'midwife-123'],
                'start_at' => ['timestampValue' => '2026-11-05T10:00:00Z'],
                'end_at' => ['timestampValue' => '2026-11-05T10:30:00Z'],
                'status' => ['stringValue' => 'available'],
            ])),
            '*documents/midwives/midwife-123?*' => Http::response($this->document('midwives/midwife-123', [
                'active' => ['booleanValue' => true],
                'verification_status' => ['stringValue' => 'verified'],
                'consultation_fee' => ['integerValue' => '0'],
            ])),
        ]);

        try {
            $this->firebase()->createBookingWithSlotHold(
                'patient-123',
                'slot-123',
                'Keluhan singkat.',
            );
            $this->fail('A midwife without a configured fee must not be bookable.');
        } catch (BookingConfigurationException) {
            $this->assertTrue(true);
        }

        Http::assertNotSent(
            static fn (Request $request): bool => str_ends_with($request->url(), ':commit'),
        );
    }

    public function test_expired_unpaid_booking_and_its_owned_slot_are_released_atomically(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'dHgx']),
            '*documents/bookings/booking-123?*' => Http::response($this->document('bookings/booking-123', [
                'slot_id' => ['stringValue' => 'slot-123'],
                'status' => ['stringValue' => 'awaiting_payment'],
                'payment_id' => ['stringValue' => 'invoice-123'],
                'hold_expires_at' => ['timestampValue' => '2026-11-04T03:59:00Z'],
            ])),
            '*documents/slots/slot-123?*' => Http::response($this->document('slots/slot-123', [
                'status' => ['stringValue' => 'held'],
                'hold_booking_id' => ['stringValue' => 'booking-123'],
                'hold_expires_at' => ['timestampValue' => '2026-11-04T03:59:00Z'],
            ])),
            '*documents/payments/invoice-123?*' => Http::response($this->document(
                'payments/invoice-123',
                ['status' => ['stringValue' => 'pending']],
            )),
            '*:commit' => Http::response(['writeResults' => [], 'commitTime' => '2026-11-04T04:00:00Z']),
        ]);

        $expired = $this->firebase()->expireBookingHold('booking-123');

        $this->assertSame(true, $expired);
        Http::assertSent(static function (Request $request): bool {
            if (! str_ends_with($request->url(), ':commit')) {
                return false;
            }

            $writes = $request->data()['writes'] ?? [];

            return count($writes) === 3
                && ($writes[0]['update']['fields']['status']['stringValue'] ?? null) === 'expired'
                && ($writes[1]['update']['fields']['status']['stringValue'] ?? null) === 'expired'
                && str_ends_with($writes[1]['update']['name'] ?? '', '/payments/invoice-123')
                && ($writes[2]['update']['fields']['status']['stringValue'] ?? null) === 'available'
                && in_array('hold_booking_id', $writes[2]['updateMask']['fieldPaths'] ?? [], true)
                && ! array_key_exists('hold_booking_id', $writes[2]['update']['fields'] ?? []);
        });
    }

    public function test_expiry_scan_queries_only_unpaid_bookings_past_the_deadline(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:runQuery' => Http::response([]),
        ]);

        $bookings = $this->firebase()->getExpiredBookingHolds();

        $this->assertSame([], $bookings);
        Http::assertSent(static function (Request $request): bool {
            $filters = $request->data()['structuredQuery']['where']['compositeFilter']['filters'] ?? [];

            return str_ends_with($request->url(), ':runQuery')
                && ($request->data()['structuredQuery']['from'][0]['collectionId'] ?? null) === 'bookings'
                && count($filters) === 2
                && ($filters[0]['fieldFilter']['field']['fieldPath'] ?? null) === 'status'
                && ($filters[0]['fieldFilter']['value']['stringValue'] ?? null) === 'awaiting_payment'
                && ($filters[1]['fieldFilter']['field']['fieldPath'] ?? null) === 'hold_expires_at'
                && ($filters[1]['fieldFilter']['op'] ?? null) === 'LESS_THAN_OR_EQUAL';
        });
    }

    public function test_attach_mayar_invoice_saves_payment_and_checkout_link_atomically(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'tx1']),
            '*documents/bookings/booking-123?*' => Http::response($this->document(
                'bookings/booking-123',
                [
                    'patient_id' => ['stringValue' => 'patient-123'],
                    'slot_id' => ['stringValue' => 'slot-123'],
                    'status' => ['stringValue' => 'awaiting_payment'],
                    'payment_id' => ['nullValue' => null],
                    'amount' => ['integerValue' => '75000'],
                    'hold_expires_at' => ['timestampValue' => '2026-11-04T04:15:00Z'],
                ],
            )),
            '*documents/slots/slot-123?*' => Http::response($this->document(
                'slots/slot-123',
                [
                    'status' => ['stringValue' => 'held'],
                    'hold_booking_id' => ['stringValue' => 'booking-123'],
                    'hold_expires_at' => ['timestampValue' => '2026-11-04T04:15:00Z'],
                ],
            )),
            '*documents/payments/invoice-123?*' => Http::response([], 404),
            '*:commit' => Http::response(['writeResults' => []]),
        ]);

        $saved = $this->firebase()->attachMayarInvoice(
            'booking-123',
            'patient-123',
            75000,
            '2026-11-04T04:15:00Z',
            [
                'id' => 'invoice-123',
                'transaction_id' => 'transaction-123',
                'link' => 'https://testingmayar.myr.id/invoices/test',
            ],
        );

        $this->assertTrue($saved);
        Http::assertSent(static function (Request $request): bool {
            if (! str_ends_with($request->url(), ':commit')) {
                return false;
            }

            $writes = $request->data()['writes'] ?? [];

            return count($writes) === 2
                && ($writes[0]['update']['name'] ?? null)
                    === 'projects/test-project/databases/(default)/documents/payments/invoice-123'
                && ($writes[0]['update']['fields']['amount']['integerValue'] ?? null) === '75000'
                && ($writes[0]['update']['fields']['environment']['stringValue'] ?? null) === 'sandbox'
                && ($writes[0]['update']['fields']['status']['stringValue'] ?? null) === 'pending'
                && ($writes[0]['currentDocument']['exists'] ?? null) === false
                && ($writes[1]['update']['fields']['payment_id']['stringValue'] ?? null) === 'invoice-123'
                && ($writes[1]['update']['fields']['checkout_url']['stringValue'] ?? null)
                    === 'https://testingmayar.myr.id/invoices/test';
        });
    }

    public function test_verified_mayar_payment_books_the_slot_and_updates_booking_atomically(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'tx1']),
            '*documents/payments/invoice-123?*' => Http::response($this->document(
                'payments/invoice-123',
                [
                    'invoice_id' => ['stringValue' => 'invoice-123'],
                    'booking_id' => ['stringValue' => 'booking-123'],
                    'amount' => ['integerValue' => '75000'],
                    'status' => ['stringValue' => 'pending'],
                ],
            )),
            '*documents/bookings/booking-123?*' => Http::response($this->document(
                'bookings/booking-123',
                [
                    'payment_id' => ['stringValue' => 'invoice-123'],
                    'slot_id' => ['stringValue' => 'slot-123'],
                    'status' => ['stringValue' => 'awaiting_payment'],
                    'hold_expires_at' => ['timestampValue' => '2026-11-04T04:15:00Z'],
                ],
            )),
            '*documents/slots/slot-123?*' => Http::response($this->document(
                'slots/slot-123',
                [
                    'status' => ['stringValue' => 'held'],
                    'hold_booking_id' => ['stringValue' => 'booking-123'],
                    'hold_expires_at' => ['timestampValue' => '2026-11-04T04:15:00Z'],
                ],
            )),
            '*:commit' => Http::response(['writeResults' => []]),
        ]);

        $result = $this->firebase()->completeMayarPayment('invoice-123', [
            'id' => 'invoice-123',
            'amount' => 75000,
            'status' => 'paid',
        ]);

        $this->assertSame('paid', $result);
        Http::assertSent(static function (Request $request): bool {
            if (! str_ends_with($request->url(), ':commit')) {
                return false;
            }

            $writes = $request->data()['writes'] ?? [];
            $bookingWrite = $writes[0] ?? [];
            $slotWrite = $writes[1] ?? [];

            return count($writes) === 3
                && ($bookingWrite['update']['fields']['status']['stringValue'] ?? null)
                    === 'paid_pending_midwife'
                && ($slotWrite['update']['fields']['status']['stringValue'] ?? null) === 'booked'
                && in_array('hold_booking_id', $slotWrite['updateMask']['fieldPaths'] ?? [], true)
                && ! array_key_exists('hold_booking_id', $slotWrite['update']['fields'] ?? [])
                && ($writes[2]['update']['fields']['status']['stringValue'] ?? null) === 'paid';
        });
    }

    public function test_paid_invoice_after_hold_expiry_requires_reconciliation_without_booking_the_slot(): void
    {
        $this->travelTo('2026-11-04 04:20:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'tx1']),
            '*documents/payments/invoice-123?*' => Http::response($this->document(
                'payments/invoice-123',
                [
                    'invoice_id' => ['stringValue' => 'invoice-123'],
                    'booking_id' => ['stringValue' => 'booking-123'],
                    'amount' => ['integerValue' => '75000'],
                    'status' => ['stringValue' => 'expired'],
                ],
            )),
            '*documents/bookings/booking-123?*' => Http::response($this->document(
                'bookings/booking-123',
                [
                    'payment_id' => ['stringValue' => 'invoice-123'],
                    'slot_id' => ['stringValue' => 'slot-123'],
                    'status' => ['stringValue' => 'expired'],
                    'hold_expires_at' => ['timestampValue' => '2026-11-04T04:15:00Z'],
                ],
            )),
            '*documents/slots/slot-123?*' => Http::response($this->document(
                'slots/slot-123',
                ['status' => ['stringValue' => 'available']],
            )),
            '*:commit' => Http::response(['writeResults' => []]),
        ]);

        $result = $this->firebase()->completeMayarPayment('invoice-123', [
            'id' => 'invoice-123',
            'amount' => 75000,
            'status' => 'paid',
        ]);

        $this->assertSame('reconciliation_required', $result);
        Http::assertSent(static function (Request $request): bool {
            if (! str_ends_with($request->url(), ':commit')) {
                return false;
            }

            $writes = $request->data()['writes'] ?? [];

            return count($writes) === 1
                && str_ends_with($writes[0]['update']['name'] ?? '', '/payments/invoice-123')
                && ($writes[0]['update']['fields']['status']['stringValue'] ?? null)
                    === 'paid_requires_reconciliation';
        });
    }

    /**
     * @param  array<string, array<string, mixed>>  $fields
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
