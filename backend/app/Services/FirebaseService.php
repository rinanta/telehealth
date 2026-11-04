<?php

namespace App\Services;

use App\Exceptions\BookingConfigurationException;
use App\Exceptions\SlotUnavailableException;
use Google\Auth\Credentials\ServiceAccountCredentials;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Kreait\Firebase\JWT\IdTokenVerifier;
use RuntimeException;

class FirebaseService
{
    /**
     * @var array<string, IdTokenVerifier>
     */
    private static array $idTokenVerifiers = [];

    public function isConfigured(): bool
    {
        return $this->projectId() !== null && is_file($this->credentialsPath());
    }

    /**
     * @return array<string, mixed>
     */
    public function verifyIdToken(string $token): array
    {
        return $this->idTokenVerifier()->verifyIdToken($token)->payload();
    }

    /**
     * @param  array<string, string|bool>  $profile
     */
    public function createUserProfile(string $uid, array $profile): bool
    {
        $response = Http::withToken($this->firestoreAccessToken())
            ->acceptJson()
            ->timeout(15)
            ->post(
                $this->documentsUrl().'/users?documentId='.rawurlencode($uid),
                ['fields' => $this->encodeFields($profile)],
            );

        if ($response->status() === 409) {
            return false;
        }

        $response->throw();

        return true;
    }

    /**
     * @return array<string, mixed>|null
     */
    public function getUserProfile(string $uid): ?array
    {
        $response = Http::withToken($this->firestoreAccessToken())
            ->acceptJson()
            ->connectTimeout(3)
            ->timeout(15)
            ->get($this->documentsUrl().'/users/'.rawurlencode($uid));

        if ($response->status() === 404) {
            return null;
        }

        $response->throw();

        return $this->decodeFields($response->json('fields', []));
    }

    /**
     * @return array<string, mixed>|null
     */
    public function getBooking(string $bookingId): ?array
    {
        $response = Http::withToken($this->firestoreAccessToken())
            ->acceptJson()
            ->connectTimeout(3)
            ->timeout(15)
            ->get($this->documentUrl('bookings', $bookingId));

        if ($response->status() === 404) {
            return null;
        }

        $response->throw();

        $booking = $this->decodeFields($response->json('fields', []));
        $booking['id'] = $bookingId;

        if (! is_string($booking['slot_start_at'] ?? null)) {
            $slotId = $booking['slot_id'] ?? null;
            if (is_string($slotId) && $slotId !== '') {
                $slotResponse = Http::withToken($this->firestoreAccessToken())
                    ->acceptJson()
                    ->connectTimeout(3)
                    ->timeout(15)
                    ->get($this->documentUrl('slots', $slotId));

                if ($slotResponse->successful()) {
                    $slot = $this->decodeFields($slotResponse->json('fields', []));
                    if (is_string($slot['start_at'] ?? null)) {
                        $booking['slot_start_at'] = $slot['start_at'];
                    }
                } elseif ($slotResponse->status() !== 404) {
                    $slotResponse->throw();
                }
            }
        }

        return $booking;
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function getBookingsForMidwife(string $midwifeId): array
    {
        return $this->runFirestoreQuery('bookings', [
            ['field' => 'midwife_id', 'value' => ['stringValue' => $midwifeId]],
        ]);
    }

    public function acceptBookingForMidwife(string $bookingId, string $midwifeId): string
    {
        return $this->transitionMidwifeBooking(
            $bookingId,
            $midwifeId,
            ['paid_pending_midwife'],
            [
                'status' => ['stringValue' => 'confirmed'],
                'confirmed_at' => ['timestampValue' => now('UTC')->toIso8601String()],
            ],
            ['status', 'confirmed_at'],
            'accepted',
        );
    }

    public function rejectBookingForMidwife(
        string $bookingId,
        string $midwifeId,
        string $reason,
    ): string {
        return $this->transitionMidwifeBooking(
            $bookingId,
            $midwifeId,
            ['paid_pending_midwife'],
            [
                'status' => ['stringValue' => 'rejected'],
                'rejection_reason' => ['stringValue' => $reason],
                'rejected_at' => ['timestampValue' => now('UTC')->toIso8601String()],
            ],
            ['status', 'rejection_reason', 'rejected_at'],
            'rejected',
        );
    }

    public function startConsultationForMidwife(string $bookingId, string $midwifeId): string
    {
        $transaction = $this->beginFirestoreTransaction();
        $booking = $this->getDocumentInTransaction('bookings', $bookingId, $transaction);

        if ($booking === null) {
            return 'not_found';
        }

        if (($booking['midwife_id'] ?? null) !== $midwifeId) {
            return 'not_owned';
        }

        if (($booking['status'] ?? null) !== 'confirmed') {
            return 'not_pending';
        }

        $slotStart = $booking['slot_start_at'] ?? null;
        if (! is_string($slotStart) || strtotime($slotStart) > now('UTC')->getTimestamp()) {
            return 'not_ready';
        }

        return $this->commitFirestoreTransaction($transaction, [
            $this->updateWrite(
                'bookings',
                $bookingId,
                [
                    'status' => ['stringValue' => 'active'],
                    'consultation_started_at' => ['timestampValue' => now('UTC')->toIso8601String()],
                ],
                ['status', 'consultation_started_at'],
            ),
        ]) ? 'started' : 'conflict';
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function getConsultationMessages(string $bookingId): array
    {
        $messages = $this->runFirestoreQuery('messages', [
            ['field' => 'booking_id', 'value' => ['stringValue' => $bookingId]],
        ]);
        usort(
            $messages,
            static fn (array $left, array $right): int => strcmp(
                (string) ($left['sent_at'] ?? ''),
                (string) ($right['sent_at'] ?? ''),
            ),
        );

        return array_slice($messages, -100);
    }

    /**
     * @return array{result: string, message?: array<string, mixed>}
     */
    public function sendConsultationMessage(
        string $bookingId,
        string $senderId,
        string $senderName,
        string $text,
    ): array {
        $transaction = $this->beginFirestoreTransaction();
        $booking = $this->getDocumentInTransaction('bookings', $bookingId, $transaction);

        if ($booking === null) {
            return ['result' => 'not_found'];
        }

        $isMidwife = ($booking['midwife_id'] ?? null) === $senderId;
        if (! $isMidwife && ($booking['patient_id'] ?? null) !== $senderId) {
            return ['result' => 'not_participant'];
        }

        if (($booking['status'] ?? null) !== 'active') {
            return ['result' => 'not_active'];
        }

        $startedAt = $booking['consultation_started_at'] ?? null;
        $startedTimestamp = is_string($startedAt) ? strtotime($startedAt) : false;
        $now = now('UTC');
        if ($startedTimestamp === false || $now->getTimestamp() >= $startedTimestamp + 1800) {
            return ['result' => 'expired'];
        }

        $messageId = (string) Str::uuid();
        $sentAt = $now->toIso8601String();
        $message = [
            'booking_id' => $bookingId,
            'sender_id' => $senderId,
            'sender_name' => $senderName,
            'text' => $text,
            'sent_at' => $sentAt,
            'is_midwife' => $isMidwife,
        ];
        $fields = [];
        foreach ($message as $key => $value) {
            $fields[$key] = is_bool($value)
                ? ['booleanValue' => $value]
                : (in_array($key, ['sent_at'], true)
                    ? ['timestampValue' => $value]
                    : ['stringValue' => $value]);
        }

        $saved = $this->commitFirestoreTransaction($transaction, [[
            'update' => [
                'name' => $this->documentName('messages', $messageId),
                'fields' => $fields,
            ],
            'currentDocument' => ['exists' => false],
        ]]);

        if (! $saved) {
            return ['result' => 'conflict'];
        }

        return ['result' => 'sent', 'message' => ['id' => $messageId, ...$message]];
    }

    /**
     * @param  list<string>  $allowedStatuses
     * @param  array<string, array<string, mixed>>  $fields
     * @param  list<string>  $fieldPaths
     */
    private function transitionMidwifeBooking(
        string $bookingId,
        string $midwifeId,
        array $allowedStatuses,
        array $fields,
        array $fieldPaths,
        string $successResult,
    ): string {
        $transaction = $this->beginFirestoreTransaction();
        $booking = $this->getDocumentInTransaction('bookings', $bookingId, $transaction);

        if ($booking === null) {
            return 'not_found';
        }

        if (($booking['midwife_id'] ?? null) !== $midwifeId) {
            return 'not_owned';
        }

        if (! in_array($booking['status'] ?? null, $allowedStatuses, true)) {
            return 'not_pending';
        }

        return $this->commitFirestoreTransaction($transaction, [
            $this->updateWrite(
                'bookings',
                $bookingId,
                $fields,
                $fieldPaths,
            ),
        ]) ? $successResult : 'conflict';
    }

    /**
     * @param  array{id: string, transaction_id: string, link: string}  $invoice  id = Midtrans order_id (booking ID), transaction_id = Snap token, link = Snap redirect URL
     */
    public function attachPaymentSession(
        string $bookingId,
        string $patientId,
        int $amount,
        string $holdExpiresAt,
        array $invoice,
    ): bool {
        $transaction = $this->beginFirestoreTransaction();
        $booking = $this->getDocumentInTransaction('bookings', $bookingId, $transaction);
        $slotId = $booking['slot_id'] ?? null;

        if (
            $booking === null
            || ($booking['patient_id'] ?? null) !== $patientId
            || ($booking['status'] ?? null) !== 'awaiting_payment'
            || ($booking['payment_id'] ?? null) !== null
            || ($booking['amount'] ?? null) !== $amount
            || ($booking['hold_expires_at'] ?? null) !== $holdExpiresAt
            || ! is_string($slotId)
            || ! $this->isFutureTimestamp($booking['hold_expires_at'] ?? null)
        ) {
            return false;
        }

        $slot = $this->getDocumentInTransaction('slots', $slotId, $transaction);
        if (
            ($slot['status'] ?? null) !== 'held'
            || ($slot['hold_booking_id'] ?? null) !== $bookingId
            || ($slot['hold_expires_at'] ?? null) !== $holdExpiresAt
            || ! $this->isFutureTimestamp($slot['hold_expires_at'] ?? null)
        ) {
            return false;
        }

        if ($this->getDocumentInTransaction('payments', $invoice['id'], $transaction) !== null) {
            return false;
        }

        $createdAt = now('UTC')->toIso8601String();

        return $this->commitFirestoreTransaction($transaction, [
            [
                'update' => [
                    'name' => $this->documentName('payments', $invoice['id']),
                    'fields' => [
                        'provider' => ['stringValue' => 'midtrans'],
                        'environment' => ['stringValue' => config('services.midtrans.environment', 'sandbox')],
                        'invoice_id' => ['stringValue' => $invoice['id']],
                        'transaction_id' => ['stringValue' => $invoice['transaction_id']],
                        'booking_id' => ['stringValue' => $bookingId],
                        'patient_id' => ['stringValue' => $patientId],
                        'amount' => ['integerValue' => (string) $amount],
                        'checkout_url' => ['stringValue' => $invoice['link']],
                        'status' => ['stringValue' => 'pending'],
                        'created_at' => ['timestampValue' => $createdAt],
                        'hold_expires_at' => ['timestampValue' => $holdExpiresAt],
                    ],
                ],
                'updateMask' => [
                    'fieldPaths' => [
                        'provider',
                        'environment',
                        'invoice_id',
                        'transaction_id',
                        'booking_id',
                        'patient_id',
                        'amount',
                        'checkout_url',
                        'status',
                        'created_at',
                        'hold_expires_at',
                    ],
                ],
                'currentDocument' => ['exists' => false],
            ],
            $this->updateWrite(
                'bookings',
                $bookingId,
                [
                    'payment_id' => ['stringValue' => $invoice['id']],
                    'payment_transaction_id' => ['stringValue' => $invoice['transaction_id']],
                    'checkout_url' => ['stringValue' => $invoice['link']],
                ],
                ['payment_id', 'payment_transaction_id', 'checkout_url'],
            ),
        ]);
    }

    /**
     * @param  array{id: string, status: string, amount: int}  $invoice  verified status from MidtransService::getStatus()
     */
    public function completePayment(string $invoiceId, array $invoice): string
    {
        $transaction = $this->beginFirestoreTransaction();
        $payment = $this->getDocumentInTransaction('payments', $invoiceId, $transaction);

        if (
            $payment === null
            || ($payment['provider'] ?? null) !== 'midtrans'
            || ($payment['invoice_id'] ?? null) !== $invoiceId
            || ($invoice['id'] ?? null) !== $invoiceId
            || ($invoice['status'] ?? null) !== 'paid'
        ) {
            return 'unmatched';
        }

        if (($payment['status'] ?? null) === 'paid') {
            return 'paid';
        }

        $paymentStatus = $payment['status'] ?? null;
        if (! in_array($paymentStatus, ['pending', 'expired'], true)) {
            return 'already_processed';
        }

        $now = now('UTC');
        $paymentFields = [
            'verified_at' => ['timestampValue' => $now->toIso8601String()],
        ];
        $paymentMask = ['verified_at'];
        $bookingId = $payment['booking_id'] ?? null;
        $booking = is_string($bookingId)
            ? $this->getDocumentInTransaction('bookings', $bookingId, $transaction)
            : null;
        $slotId = $booking['slot_id'] ?? null;
        $slot = is_string($slotId)
            ? $this->getDocumentInTransaction('slots', $slotId, $transaction)
            : null;

        if (($invoice['amount'] ?? null) !== ($payment['amount'] ?? null)) {
            $paymentFields['status'] = ['stringValue' => 'paid_requires_reconciliation'];
            $paymentFields['reconciliation_reason'] = ['stringValue' => 'amount_mismatch'];
            $paymentMask = [...$paymentMask, 'status', 'reconciliation_reason'];
            $result = 'reconciliation_required';
            $writes = [
                $this->updateWrite('payments', $invoiceId, $paymentFields, $paymentMask),
            ];
        } elseif (
            $paymentStatus === 'expired'
            || ! is_string($bookingId)
            || $booking === null
            || ($booking['payment_id'] ?? null) !== $invoiceId
            || ($booking['status'] ?? null) !== 'awaiting_payment'
            || ! $this->isFutureTimestamp($booking['hold_expires_at'] ?? null)
            || ! is_string($slotId)
            || $slot === null
            || ($slot['status'] ?? null) !== 'held'
            || ($slot['hold_booking_id'] ?? null) !== $bookingId
            || ! $this->isFutureTimestamp($slot['hold_expires_at'] ?? null)
        ) {
            $paymentFields['status'] = ['stringValue' => 'paid_requires_reconciliation'];
            $paymentFields['reconciliation_reason'] = ['stringValue' => 'hold_expired_or_released'];
            $paymentMask = [...$paymentMask, 'status', 'reconciliation_reason'];
            $result = 'reconciliation_required';
            $writes = [
                $this->updateWrite('payments', $invoiceId, $paymentFields, $paymentMask),
            ];
        } else {
            $paymentFields['status'] = ['stringValue' => 'paid'];
            $paymentMask[] = 'status';
            $result = 'paid';
            $writes = [
                $this->updateWrite(
                    'bookings',
                    $bookingId,
                    [
                        'status' => ['stringValue' => 'paid_pending_midwife'],
                        'paid_at' => ['timestampValue' => $now->toIso8601String()],
                    ],
                    ['status', 'paid_at'],
                ),
                [
                    'update' => [
                        'name' => $this->documentName('slots', $slotId),
                        'fields' => ['status' => ['stringValue' => 'booked']],
                    ],
                    'updateMask' => [
                        'fieldPaths' => ['status', 'hold_booking_id', 'hold_expires_at'],
                    ],
                ],
                $this->updateWrite('payments', $invoiceId, $paymentFields, $paymentMask),
            ];
        }

        return $this->commitFirestoreTransaction($transaction, $writes) ? $result : 'retry';
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function getActiveVerifiedMidwives(): array
    {
        return $this->runFirestoreQuery('midwives', [
            ['field' => 'active', 'value' => ['booleanValue' => true]],
            ['field' => 'verification_status', 'value' => ['stringValue' => 'verified']],
        ]);
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function getAvailableSlots(string $midwifeId): array
    {
        return $this->runFirestoreQuery('slots', [
            ['field' => 'midwife_id', 'value' => ['stringValue' => $midwifeId]],
            ['field' => 'status', 'value' => ['stringValue' => 'available']],
            ['field' => 'start_at', 'operator' => 'GREATER_THAN', 'value' => [
                'timestampValue' => now()->toIso8601String(),
            ]],
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    public function createBookingWithSlotHold(
        string $patientId,
        string $slotId,
        string $complaint,
    ): array {
        $holdMinutes = (int) config('booking.hold_minutes', 15);
        if ($holdMinutes < 1) {
            throw new RuntimeException('BOOKING_HOLD_MINUTES must be a positive integer.');
        }

        $bookingId = (string) Str::uuid();
        $transaction = $this->beginFirestoreTransaction();
        $slot = $this->getDocumentInTransaction('slots', $slotId, $transaction);

        if ($slot === null) {
            throw new SlotUnavailableException;
        }

        $midwifeId = $slot['midwife_id'] ?? null;
        $slotStart = $slot['start_at'] ?? null;
        $slotEnd = $slot['end_at'] ?? null;
        $slotStartTimestamp = is_string($slotStart) ? strtotime($slotStart) : false;
        $slotEndTimestamp = is_string($slotEnd) ? strtotime($slotEnd) : false;
        $nowTimestamp = now('UTC')->getTimestamp();

        if (
            ! is_string($midwifeId)
            || $slotStartTimestamp === false
            || $slotEndTimestamp === false
            || $slotStartTimestamp <= $nowTimestamp
            || $slotEndTimestamp - $slotStartTimestamp !== 1800
        ) {
            throw new SlotUnavailableException;
        }

        $expiredBooking = null;
        $expiredPayment = null;
        if (($slot['status'] ?? null) === 'available') {
            if (! empty($slot['hold_booking_id']) || ! empty($slot['hold_expires_at'])) {
                throw new SlotUnavailableException;
            }
        } elseif (($slot['status'] ?? null) === 'held') {
            $holdExpiresAt = $slot['hold_expires_at'] ?? null;
            $holdExpiresTimestamp = is_string($holdExpiresAt) ? strtotime($holdExpiresAt) : false;
            $existingBookingId = $slot['hold_booking_id'] ?? null;

            if (
                $holdExpiresTimestamp === false
                || $holdExpiresTimestamp > $nowTimestamp
                || ! is_string($existingBookingId)
                || $existingBookingId === ''
            ) {
                throw new SlotUnavailableException;
            }

            $expiredBooking = $this->getDocumentInTransaction(
                'bookings',
                $existingBookingId,
                $transaction,
            );

            if (
                $expiredBooking !== null
                && (
                    ($expiredBooking['slot_id'] ?? null) !== $slotId
                    || ! in_array(
                        $expiredBooking['status'] ?? null,
                        ['awaiting_payment', 'expired', 'payment_failed', 'cancelled'],
                        true,
                    )
                    || (
                        ($expiredBooking['status'] ?? null) === 'awaiting_payment'
                        && ! $this->isExpiredTimestamp(
                            $expiredBooking['hold_expires_at'] ?? null,
                            $nowTimestamp,
                        )
                    )
                )
            ) {
                throw new SlotUnavailableException;
            }

            if (
                ($expiredBooking['status'] ?? null) === 'awaiting_payment'
                && is_string($expiredBooking['payment_id'] ?? null)
            ) {
                $expiredPayment = $this->getDocumentInTransaction(
                    'payments',
                    $expiredBooking['payment_id'],
                    $transaction,
                );
            }
        } else {
            throw new SlotUnavailableException;
        }

        $midwife = $this->getDocumentInTransaction('midwives', $midwifeId, $transaction);
        $consultationFee = $midwife['consultation_fee'] ?? null;

        if (
            $midwife === null
            || ($midwife['active'] ?? null) !== true
            || ($midwife['verification_status'] ?? null) !== 'verified'
        ) {
            throw new BookingConfigurationException;
        }

        if (! is_int($consultationFee) || $consultationFee < 1) {
            throw new BookingConfigurationException;
        }

        $createdAt = now('UTC');
        $holdExpiresAt = $createdAt->copy()->addMinutes($holdMinutes);
        $slotPath = $this->documentName('slots', $slotId);
        $bookingPath = $this->documentName('bookings', $bookingId);
        $writes = [
            [
                'update' => [
                    'name' => $slotPath,
                    'fields' => [
                        'status' => ['stringValue' => 'held'],
                        'hold_booking_id' => ['stringValue' => $bookingId],
                        'hold_expires_at' => ['timestampValue' => $holdExpiresAt->toIso8601String()],
                    ],
                ],
                'updateMask' => [
                    'fieldPaths' => ['status', 'hold_booking_id', 'hold_expires_at'],
                ],
            ],
        ];

        if (
            $expiredBooking !== null
            && ($expiredBooking['status'] ?? null) === 'awaiting_payment'
        ) {
            $writes[] = $this->updateWrite(
                'bookings',
                (string) $expiredBooking['id'],
                [
                    'status' => ['stringValue' => 'expired'],
                    'expired_at' => ['timestampValue' => $createdAt->toIso8601String()],
                ],
                ['status', 'expired_at'],
            );

            if (
                $expiredPayment !== null
                && ($expiredPayment['status'] ?? null) === 'pending'
            ) {
                $writes[] = $this->updateWrite(
                    'payments',
                    (string) $expiredPayment['id'],
                    [
                        'status' => ['stringValue' => 'expired'],
                        'expired_at' => ['timestampValue' => $createdAt->toIso8601String()],
                    ],
                    ['status', 'expired_at'],
                );
            }
        }

        $writes[] = [
            'update' => [
                'name' => $bookingPath,
                'fields' => [
                    'patient_id' => ['stringValue' => $patientId],
                    'midwife_id' => ['stringValue' => $midwifeId],
                    'slot_id' => ['stringValue' => $slotId],
                    'slot_start_at' => ['timestampValue' => $slotStart],
                    'complaint' => ['stringValue' => $complaint],
                    'amount' => ['integerValue' => (string) $consultationFee],
                    'status' => ['stringValue' => 'awaiting_payment'],
                    'payment_id' => ['nullValue' => null],
                    'created_at' => ['timestampValue' => $createdAt->toIso8601String()],
                    'hold_expires_at' => ['timestampValue' => $holdExpiresAt->toIso8601String()],
                ],
            ],
            'updateMask' => [
                'fieldPaths' => [
                    'patient_id',
                    'midwife_id',
                    'slot_id',
                    'slot_start_at',
                    'complaint',
                    'amount',
                    'status',
                    'payment_id',
                    'created_at',
                    'hold_expires_at',
                ],
            ],
            'currentDocument' => ['exists' => false],
        ];

        if (! $this->commitFirestoreTransaction($transaction, $writes)) {
            throw new SlotUnavailableException;
        }

        return [
            'id' => $bookingId,
            'patient_id' => $patientId,
            'midwife_id' => $midwifeId,
            'slot_id' => $slotId,
            'slot_start_at' => $slotStart,
            'amount' => $consultationFee,
            'status' => 'awaiting_payment',
            'created_at' => $createdAt->toIso8601String(),
            'hold_expires_at' => $holdExpiresAt->toIso8601String(),
        ];
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function getExpiredBookingHolds(): array
    {
        return $this->runFirestoreQuery('bookings', [
            ['field' => 'status', 'value' => ['stringValue' => 'awaiting_payment']],
            [
                'field' => 'hold_expires_at',
                'operator' => 'LESS_THAN_OR_EQUAL',
                'value' => ['timestampValue' => now('UTC')->toIso8601String()],
            ],
        ]);
    }

    public function expireBookingHold(string $bookingId): bool
    {
        $transaction = $this->beginFirestoreTransaction();
        $booking = $this->getDocumentInTransaction('bookings', $bookingId, $transaction);
        $now = now('UTC');

        if (
            $booking === null
            || ($booking['status'] ?? null) !== 'awaiting_payment'
            || ! $this->isExpiredTimestamp($booking['hold_expires_at'] ?? null, $now->getTimestamp())
        ) {
            return false;
        }

        $slotId = $booking['slot_id'] ?? null;
        if (! is_string($slotId) || $slotId === '') {
            return false;
        }

        $slot = $this->getDocumentInTransaction('slots', $slotId, $transaction);
        $writes = [
            $this->updateWrite(
                'bookings',
                $bookingId,
                [
                    'status' => ['stringValue' => 'expired'],
                    'expired_at' => ['timestampValue' => $now->toIso8601String()],
                ],
                ['status', 'expired_at'],
            ),
        ];

        $paymentId = $booking['payment_id'] ?? null;
        if (is_string($paymentId) && $paymentId !== '') {
            $payment = $this->getDocumentInTransaction('payments', $paymentId, $transaction);
            if ($payment !== null && ($payment['status'] ?? null) === 'pending') {
                $writes[] = $this->updateWrite(
                    'payments',
                    $paymentId,
                    [
                        'status' => ['stringValue' => 'expired'],
                        'expired_at' => ['timestampValue' => $now->toIso8601String()],
                    ],
                    ['status', 'expired_at'],
                );
            }
        }

        if (
            ($slot['status'] ?? null) === 'held'
            && ($slot['hold_booking_id'] ?? null) === $bookingId
        ) {
            if (! $this->isExpiredTimestamp($slot['hold_expires_at'] ?? null, $now->getTimestamp())) {
                return false;
            }

            $writes[] = [
                'update' => [
                    'name' => $this->documentName('slots', $slotId),
                    'fields' => [
                        'status' => ['stringValue' => 'available'],
                    ],
                ],
                'updateMask' => [
                    'fieldPaths' => ['status', 'hold_booking_id', 'hold_expires_at'],
                ],
            ];
        }

        return $this->commitFirestoreTransaction($transaction, $writes);
    }

    private function idTokenVerifier(): IdTokenVerifier
    {
        $projectId = $this->projectId();

        if ($projectId === null) {
            throw new RuntimeException('FIREBASE_PROJECT_ID is not configured.');
        }

        return self::$idTokenVerifiers[$projectId]
            ??= IdTokenVerifier::createWithProjectId($projectId);
    }

    private function projectId(): ?string
    {
        $projectId = config('firebase.project_id');

        return is_string($projectId) && $projectId !== '' ? $projectId : null;
    }

    private function credentialsPath(): string
    {
        $path = (string) config('firebase.credentials');

        if (
            str_starts_with($path, '/')
            || str_starts_with($path, '\\')
            || preg_match('/^[A-Za-z]:[\/\\\\]/', $path) === 1
        ) {
            return $path;
        }

        return base_path($path);
    }

    protected function firestoreAccessToken(): string
    {
        $projectId = $this->projectId();
        $credentialsPath = $this->credentialsPath();

        if ($projectId === null || ! is_file($credentialsPath)) {
            throw new RuntimeException('Firebase service-account credentials are not configured.');
        }

        $cacheKey = 'firebase.firestore.access_token.'.$projectId;
        $cache = Cache::store('file');
        $cachedToken = $cache->get($cacheKey);

        if (is_string($cachedToken)) {
            return $cachedToken;
        }

        $credentials = new ServiceAccountCredentials(
            'https://www.googleapis.com/auth/datastore',
            $credentialsPath,
        );
        $tokenResponse = $credentials->fetchAuthToken();
        $accessToken = $tokenResponse['access_token'] ?? null;

        if (! is_string($accessToken) || $accessToken === '') {
            throw new RuntimeException('Google Auth did not return a Firestore access token.');
        }

        $expiresIn = max(60, (int) ($tokenResponse['expires_in'] ?? 3600) - 60);
        $cache->put($cacheKey, $accessToken, now()->addSeconds($expiresIn));

        return $accessToken;
    }

    /**
     * @param  list<array{field: string, value: array<string, mixed>, operator?: string}>  $filters
     * @return list<array<string, mixed>>
     */
    private function runFirestoreQuery(string $collection, array $filters): array
    {
        $structuredFilters = array_map(
            static fn (array $filter): array => [
                'fieldFilter' => [
                    'field' => ['fieldPath' => $filter['field']],
                    'op' => $filter['operator'] ?? 'EQUAL',
                    'value' => $filter['value'],
                ],
            ],
            $filters,
        );

        $response = Http::withToken($this->firestoreAccessToken())
            ->acceptJson()
            ->connectTimeout(3)
            ->timeout(15)
            ->post($this->documentsUrl().':runQuery', [
                'structuredQuery' => [
                    'from' => [['collectionId' => $collection]],
                    'where' => [
                        'compositeFilter' => [
                            'op' => 'AND',
                            'filters' => $structuredFilters,
                        ],
                    ],
                    'limit' => 100,
                ],
            ]);

        $response->throw();

        $rows = $response->json();
        if (! is_array($rows)) {
            throw new RuntimeException('Firestore returned an invalid query response.');
        }

        $documents = [];
        foreach ($rows as $row) {
            if (! is_array($row) || ! is_array($row['document'] ?? null)) {
                continue;
            }

            $document = $row['document'];
            $fields = $this->decodeFields(is_array($document['fields'] ?? null) ? $document['fields'] : []);
            $name = $document['name'] ?? null;

            if (is_string($name)) {
                $fields['id'] = basename($name);
            }

            $documents[] = $fields;
        }

        return $documents;
    }

    private function beginFirestoreTransaction(): string
    {
        $response = Http::withToken($this->firestoreAccessToken())
            ->acceptJson()
            ->connectTimeout(3)
            ->timeout(15)
            ->post($this->documentsUrl().':beginTransaction', [
                'options' => ['readWrite' => new \stdClass],
            ]);
        $response->throw();

        $transaction = $response->json('transaction');
        if (! is_string($transaction) || $transaction === '') {
            throw new RuntimeException('Firestore did not return a transaction ID.');
        }

        return $transaction;
    }

    /**
     * @return array<string, mixed>|null
     */
    private function getDocumentInTransaction(
        string $collection,
        string $documentId,
        string $transaction,
    ): ?array {
        $response = Http::withToken($this->firestoreAccessToken())
            ->acceptJson()
            ->connectTimeout(3)
            ->timeout(15)
            ->get(
                $this->documentUrl($collection, $documentId),
                ['transaction' => $transaction],
            );

        if ($response->status() === 404) {
            return null;
        }

        $response->throw();
        $document = $response->json();
        if (! is_array($document)) {
            throw new RuntimeException('Firestore returned an invalid document response.');
        }

        $fields = $this->decodeFields(
            is_array($document['fields'] ?? null) ? $document['fields'] : [],
        );
        $fields['id'] = $documentId;
        $fields['update_time'] = $document['updateTime'] ?? null;

        return $fields;
    }

    /**
     * @param  list<array<string, mixed>>  $writes
     */
    private function commitFirestoreTransaction(string $transaction, array $writes): bool
    {
        $response = Http::withToken($this->firestoreAccessToken())
            ->acceptJson()
            ->connectTimeout(3)
            ->timeout(15)
            ->post($this->documentsUrl().':commit', [
                'transaction' => $transaction,
                'writes' => $writes,
            ]);

        if ($response->status() === 409) {
            return false;
        }

        $response->throw();

        return true;
    }

    private function documentName(string $collection, string $documentId): string
    {
        return $this->documentsResourceName().'/'.$collection.'/'.rawurlencode($documentId);
    }

    private function documentUrl(string $collection, string $documentId): string
    {
        return $this->documentsUrl().'/'.$collection.'/'.rawurlencode($documentId);
    }

    private function documentsResourceName(): string
    {
        return substr($this->documentsUrl(), strlen('https://firestore.googleapis.com/v1/'));
    }

    /**
     * @param  array<string, array<string, mixed>>  $fields
     * @param  list<string>  $fieldPaths
     * @return array<string, mixed>
     */
    private function updateWrite(
        string $collection,
        string $documentId,
        array $fields,
        array $fieldPaths,
    ): array {
        return [
            'update' => [
                'name' => $this->documentName($collection, $documentId),
                'fields' => $fields,
            ],
            'updateMask' => ['fieldPaths' => $fieldPaths],
        ];
    }

    private function isExpiredTimestamp(mixed $timestamp, int $now): bool
    {
        $expiresAt = is_string($timestamp) ? strtotime($timestamp) : false;

        return $expiresAt !== false && $expiresAt <= $now;
    }

    private function isFutureTimestamp(mixed $timestamp): bool
    {
        $expiresAt = is_string($timestamp) ? strtotime($timestamp) : false;

        return $expiresAt !== false && $expiresAt > now('UTC')->getTimestamp();
    }

    private function documentsUrl(): string
    {
        $projectId = $this->projectId();

        if ($projectId === null) {
            throw new RuntimeException('FIREBASE_PROJECT_ID is not configured.');
        }

        return 'https://firestore.googleapis.com/v1/projects/'
            .$projectId.'/databases/(default)/documents';
    }

    /**
     * @param  array<string, string|bool>  $fields
     * @return array<string, array{stringValue?: string, booleanValue?: bool}>
     */
    private function encodeFields(array $fields): array
    {
        $encoded = [];

        foreach ($fields as $name => $value) {
            $encoded[$name] = is_bool($value)
                ? ['booleanValue' => $value]
                : ['stringValue' => $value];
        }

        return $encoded;
    }

    /**
     * @param  array<string, mixed>  $fields
     * @return array<string, mixed>
     */
    private function decodeFields(array $fields): array
    {
        $decoded = [];

        foreach ($fields as $name => $field) {
            if (is_array($field)) {
                $decoded[$name] = $this->decodeValue($field);
            }
        }

        return $decoded;
    }

    /**
     * @param  array<string, mixed>  $value
     */
    private function decodeValue(array $value): mixed
    {
        foreach ([
            'stringValue',
            'booleanValue',
            'timestampValue',
            'integerValue',
            'doubleValue',
            'nullValue',
            'referenceValue',
        ] as $type) {
            if (array_key_exists($type, $value)) {
                return $type === 'integerValue' ? (int) $value[$type] : $value[$type];
            }
        }

        if (is_array($value['mapValue']['fields'] ?? null)) {
            return $this->decodeFields($value['mapValue']['fields']);
        }

        if (is_array($value['arrayValue']['values'] ?? null)) {
            return array_map(
                fn (mixed $item): mixed => is_array($item) ? $this->decodeValue($item) : null,
                $value['arrayValue']['values'],
            );
        }

        return null;
    }
}
