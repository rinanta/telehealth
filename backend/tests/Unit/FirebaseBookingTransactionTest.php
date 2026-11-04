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

    public function test_midwife_booking_query_is_scoped_to_the_authenticated_midwife(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            '*:runQuery' => Http::response([[
                'document' => $this->document('bookings/booking-123', [
                    'midwife_id' => ['stringValue' => 'midwife-123'],
                    'status' => ['stringValue' => 'paid_pending_midwife'],
                ]),
            ]]),
        ]);

        $bookings = $this->firebase()->getBookingsForMidwife('midwife-123');

        $this->assertSame('booking-123', $bookings[0]['id']);
        Http::assertSent(static function (Request $request): bool {
            $filters = $request->data()['structuredQuery']['where']['compositeFilter']['filters'] ?? [];

            return str_ends_with($request->url(), ':runQuery')
                && ($request->data()['structuredQuery']['from'][0]['collectionId'] ?? null) === 'bookings'
                && count($filters) === 1
                && ($filters[0]['fieldFilter']['field']['fieldPath'] ?? null) === 'midwife_id'
                && ($filters[0]['fieldFilter']['value']['stringValue'] ?? null) === 'midwife-123';
        });
    }

    public function test_midwife_acceptance_transaction_confirms_only_her_paid_booking(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'tx1']),
            '*documents/bookings/booking-123?*' => Http::response($this->document(
                'bookings/booking-123',
                [
                    'midwife_id' => ['stringValue' => 'midwife-123'],
                    'status' => ['stringValue' => 'paid_pending_midwife'],
                ],
            )),
            '*:commit' => Http::response(['writeResults' => []]),
        ]);

        $result = $this->firebase()->acceptBookingForMidwife('booking-123', 'midwife-123');

        $this->assertSame('accepted', $result);
        Http::assertSent(static function (Request $request): bool {
            if (! str_ends_with($request->url(), ':commit')) {
                return false;
            }

            $writes = $request->data()['writes'] ?? [];

            return count($writes) === 1
                && ($writes[0]['update']['fields']['status']['stringValue'] ?? null) === 'confirmed'
                && in_array('confirmed_at', $writes[0]['updateMask']['fieldPaths'] ?? [], true)
                && ($request->data()['transaction'] ?? null) === 'tx1';
        });
    }

    public function test_midwife_can_start_its_confirmed_booking_at_the_scheduled_time(): void
    {
        $this->travelTo('2026-11-05 10:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'tx1']),
            '*documents/bookings/booking-123?*' => Http::response($this->document(
                'bookings/booking-123',
                [
                    'midwife_id' => ['stringValue' => 'midwife-123'],
                    'slot_start_at' => ['timestampValue' => '2026-11-05T10:00:00Z'],
                    'status' => ['stringValue' => 'confirmed'],
                ],
            )),
            '*:commit' => Http::response(['writeResults' => []]),
        ]);

        $result = $this->firebase()->startConsultationForMidwife(
            'booking-123',
            'midwife-123',
        );

        $this->assertSame('started', $result);
        Http::assertSent(static function (Request $request): bool {
            $writes = $request->data()['writes'] ?? [];

            return str_ends_with($request->url(), ':commit')
                && ($writes[0]['update']['fields']['status']['stringValue'] ?? null) === 'active'
                && array_key_exists(
                    'consultation_started_at',
                    $writes[0]['update']['fields'] ?? [],
                );
        });
    }

    public function test_midwife_cannot_start_a_confirmed_booking_before_its_slot_time(): void
    {
        $this->travelTo('2026-11-05 09:59:59 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'tx1']),
            '*documents/bookings/booking-123?*' => Http::response($this->document(
                'bookings/booking-123',
                [
                    'midwife_id' => ['stringValue' => 'midwife-123'],
                    'slot_start_at' => ['timestampValue' => '2026-11-05T10:00:00Z'],
                    'status' => ['stringValue' => 'confirmed'],
                ],
            )),
        ]);

        $result = $this->firebase()->startConsultationForMidwife(
            'booking-123',
            'midwife-123',
        );

        $this->assertSame('not_ready', $result);
        Http::assertNotSent(
            static fn (Request $request): bool => str_ends_with($request->url(), ':commit'),
        );
    }

    public function test_consultation_message_is_written_only_during_active_session(): void
    {
        $this->travelTo('2026-11-05 10:10:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'tx1']),
            '*documents/bookings/booking-123?*' => Http::response($this->document(
                'bookings/booking-123',
                [
                    'patient_id' => ['stringValue' => 'patient-123'],
                    'midwife_id' => ['stringValue' => 'midwife-123'],
                    'status' => ['stringValue' => 'active'],
                    'consultation_started_at' => ['timestampValue' => '2026-11-05T10:00:00Z'],
                ],
            )),
            '*:commit' => Http::response(['writeResults' => []]),
        ]);

        $result = $this->firebase()->sendConsultationMessage(
            'booking-123',
            'patient-123',
            'Bunda',
            'Halo, Bidan.',
        );

        $this->assertSame('sent', $result['result']);
        $this->assertSame('Halo, Bidan.', $result['message']['text']);
        Http::assertSent(static function (Request $request): bool {
            $writes = $request->data()['writes'] ?? [];
            $fields = $writes[0]['update']['fields'] ?? [];

            return str_ends_with($request->url(), ':commit')
                && count($writes) === 1
                && str_contains($writes[0]['update']['name'] ?? '', '/documents/messages/')
                && ($fields['booking_id']['stringValue'] ?? null) === 'booking-123'
                && ($fields['sender_id']['stringValue'] ?? null) === 'patient-123'
                && ($fields['is_midwife']['booleanValue'] ?? null) === false
                && ($fields['text']['stringValue'] ?? null) === 'Halo, Bidan.'
                && ($writes[0]['currentDocument']['exists'] ?? null) === false;
        });
    }

    public function test_consultation_message_is_rejected_after_thirty_minutes(): void
    {
        $this->travelTo('2026-11-05 10:30:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'tx1']),
            '*documents/bookings/booking-123?*' => Http::response($this->document(
                'bookings/booking-123',
                [
                    'patient_id' => ['stringValue' => 'patient-123'],
                    'midwife_id' => ['stringValue' => 'midwife-123'],
                    'status' => ['stringValue' => 'active'],
                    'consultation_started_at' => ['timestampValue' => '2026-11-05T10:00:00Z'],
                ],
            )),
        ]);

        $result = $this->firebase()->sendConsultationMessage(
            'booking-123',
            'patient-123',
            'Bunda',
            'Pesan terlambat.',
        );

        $this->assertSame('expired', $result['result']);
        Http::assertNotSent(
            static fn (Request $request): bool => str_ends_with($request->url(), ':commit'),
        );
    }

    public function test_consultation_messages_are_loaded_for_the_booking(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            '*:runQuery' => Http::response([[
                'document' => $this->document('messages/message-123', [
                    'booking_id' => ['stringValue' => 'booking-123'],
                    'sender_id' => ['stringValue' => 'patient-123'],
                    'text' => ['stringValue' => 'Halo.'],
                    'sent_at' => ['timestampValue' => '2026-11-05T10:01:00Z'],
                ]),
            ]]),
        ]);

        $messages = $this->firebase()->getConsultationMessages('booking-123');

        $this->assertCount(1, $messages);
        $this->assertSame('message-123', $messages[0]['id']);
        Http::assertSent(static function (Request $request): bool {
            $filters = $request->data()['structuredQuery']['where']['compositeFilter']['filters'] ?? [];

            return str_ends_with($request->url(), ':runQuery')
                && ($request->data()['structuredQuery']['from'][0]['collectionId'] ?? null) === 'messages'
                && ($filters[0]['fieldFilter']['field']['fieldPath'] ?? null) === 'booking_id'
                && ($filters[0]['fieldFilter']['value']['stringValue'] ?? null) === 'booking-123';
        });
    }

    public function test_attach_payment_session_saves_payment_and_checkout_link_atomically(): void
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

        $saved = $this->firebase()->attachPaymentSession(
            'booking-123',
            'patient-123',
            75000,
            '2026-11-04T04:15:00Z',
            [
                'id' => 'invoice-123',
                'transaction_id' => 'snap-token-123',
                'link' => 'https://app.sandbox.midtrans.com/snap/v4/redirection/snap-token-123',
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
                && ($writes[0]['update']['fields']['provider']['stringValue'] ?? null) === 'midtrans'
                && ($writes[0]['update']['fields']['environment']['stringValue'] ?? null) === 'sandbox'
                && ($writes[0]['update']['fields']['status']['stringValue'] ?? null) === 'pending'
                && ($writes[0]['currentDocument']['exists'] ?? null) === false
                && ($writes[1]['update']['fields']['payment_id']['stringValue'] ?? null) === 'invoice-123'
                && ($writes[1]['update']['fields']['checkout_url']['stringValue'] ?? null)
                    === 'https://app.sandbox.midtrans.com/snap/v4/redirection/snap-token-123';
        });
    }

    public function test_verified_payment_books_the_slot_and_updates_booking_atomically(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'tx1']),
            '*documents/payments/invoice-123?*' => Http::response($this->document(
                'payments/invoice-123',
                [
                    'provider' => ['stringValue' => 'midtrans'],
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

        $result = $this->firebase()->completePayment('invoice-123', [
            'id' => 'invoice-123',
            'status' => 'paid',
            'amount' => 75000,
            'transaction_status' => 'settlement',
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
                    'provider' => ['stringValue' => 'midtrans'],
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

        $result = $this->firebase()->completePayment('invoice-123', [
            'id' => 'invoice-123',
            'status' => 'paid',
            'amount' => 75000,
            'transaction_status' => 'settlement',
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

    public function test_payment_from_another_provider_is_never_completed(): void
    {
        $this->travelTo('2026-11-04 04:00:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'tx1']),
            '*documents/payments/invoice-123?*' => Http::response($this->document(
                'payments/invoice-123',
                [
                    'provider' => ['stringValue' => 'legacy-provider'],
                    'invoice_id' => ['stringValue' => 'invoice-123'],
                    'booking_id' => ['stringValue' => 'booking-123'],
                    'amount' => ['integerValue' => '75000'],
                    'status' => ['stringValue' => 'pending'],
                ],
            )),
        ]);

        $result = $this->firebase()->completePayment('invoice-123', [
            'id' => 'invoice-123',
            'status' => 'paid',
            'amount' => 75000,
            'transaction_status' => 'settlement',
        ]);

        $this->assertSame('unmatched', $result);
    }

    public function test_get_confirmed_bookings_past_no_show_deadline_queries_firestore(): void
    {
        $this->travelTo('2026-11-05 10:15:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:runQuery' => Http::response([
                [
                    'document' => $this->document('bookings/booking-late', [
                        'midwife_id' => ['stringValue' => 'midwife-123'],
                        'status' => ['stringValue' => 'confirmed'],
                        'slot_start_at' => ['timestampValue' => '2026-11-05T10:00:00Z'],
                    ]),
                ],
            ]),
        ]);

        $bookings = $this->firebase()->getConfirmedBookingsPastNoShowDeadline(10);

        $this->assertCount(1, $bookings);
        $this->assertSame('booking-late', $bookings[0]['id']);

        Http::assertSent(static function (Request $request): bool {
            $filters = $request->data()['structuredQuery']['where']['compositeFilter']['filters'] ?? [];

            return count($filters) === 2
                && ($filters[0]['fieldFilter']['field']['fieldPath'] ?? null) === 'status'
                && ($filters[0]['fieldFilter']['value']['stringValue'] ?? null) === 'confirmed'
                && ($filters[1]['fieldFilter']['field']['fieldPath'] ?? null) === 'slot_start_at'
                && ($filters[1]['fieldFilter']['op'] ?? null) === 'LESS_THAN_OR_EQUAL';
        });
    }

    public function test_mark_booking_as_no_show_updates_status_atomically(): void
    {
        $this->travelTo('2026-11-05 10:15:00 UTC');
        Http::preventStrayRequests();
        Http::fake([
            '*:beginTransaction' => Http::response(['transaction' => 'tx1']),
            '*documents/bookings/booking-123?*' => Http::response($this->document(
                'bookings/booking-123',
                [
                    'midwife_id' => ['stringValue' => 'midwife-123'],
                    'slot_start_at' => ['timestampValue' => '2026-11-05T10:00:00Z'],
                    'status' => ['stringValue' => 'confirmed'],
                ],
            )),
            '*:commit' => Http::response(['writeResults' => []]),
        ]);

        $result = $this->firebase()->markBookingAsNoShow('booking-123', 10);

        $this->assertTrue($result);
        Http::assertSent(static function (Request $request): bool {
            $writes = $request->data()['writes'] ?? [];

            return str_ends_with($request->url(), ':commit')
                && ($writes[0]['update']['fields']['status']['stringValue'] ?? null) === 'no_show'
                && in_array('no_show_at', $writes[0]['updateMask']['fieldPaths'] ?? [], true);
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
