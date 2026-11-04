<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ConsultationChatController extends Controller
{
    public function index(
        string $id,
        Request $request,
        FirebaseService $firebase,
    ): JsonResponse {
        $context = $this->participantContext($id, $request, $firebase);
        if ($context instanceof JsonResponse) {
            return $context;
        }

        [$booking, $currentProfile, $otherProfile] = $context;
        if (! in_array($booking['status'] ?? null, ['active', 'completed'], true)) {
            return response()->json([
                'message' => 'The consultation chat is available after the midwife starts the session.',
                'code' => 'consultation_not_active',
            ], 409);
        }

        $endsAt = $booking['ends_at'] ?? null;
        $endsTimestamp = is_string($endsAt) ? strtotime($endsAt) : false;
        if ($endsTimestamp === false) {
            $startedAt = $booking['consultation_started_at'] ?? null;
            $startedTimestamp = is_string($startedAt) ? strtotime($startedAt) : false;
            $endsTimestamp = $startedTimestamp !== false ? $startedTimestamp + 1800 : false;
        }

        $canSend = ($booking['status'] ?? null) === 'active'
            && $endsTimestamp !== false
            && now('UTC')->getTimestamp() < $endsTimestamp;

        return response()->json(['data' => [
            'booking' => $this->publicBooking(
                $id,
                $booking,
                $currentProfile,
                $otherProfile,
            ),
            'messages' => $firebase->getConsultationMessages($id),
            'can_send' => $canSend,
        ]]);
    }

    public function store(
        string $id,
        Request $request,
        FirebaseService $firebase,
    ): JsonResponse {
        $data = $request->validate([
            'text' => ['required', 'string', 'max:2000'],
        ]);
        $context = $this->participantContext($id, $request, $firebase);
        if ($context instanceof JsonResponse) {
            return $context;
        }

        [, $currentProfile] = $context;
        $result = $firebase->sendConsultationMessage(
            $id,
            $request->attributes->get('firebase_uid'),
            $currentProfile['name'],
            trim($data['text']),
        );

        if (in_array($result['result'], ['not_found', 'not_participant'], true)) {
            return response()->json([
                'message' => 'Booking not found.',
                'code' => 'booking_not_found',
            ], 404);
        }

        if ($result['result'] !== 'sent') {
            $code = $result['result'] === 'expired'
                ? 'consultation_expired'
                : 'consultation_not_active';

            return response()->json([
                'message' => 'This consultation is no longer accepting messages.',
                'code' => $code,
            ], 409);
        }

        return response()->json(['data' => $result['message']], 201);
    }

    /**
     * @return array{array<string, mixed>, array<string, mixed>, array<string, mixed>}|JsonResponse
     */
    private function participantContext(
        string $bookingId,
        Request $request,
        FirebaseService $firebase,
    ): array|JsonResponse {
        $uid = $request->attributes->get('firebase_uid');
        $profile = $request->attributes->get('firebase_profile')
            ?? $firebase->getUserProfile($uid);
        $booking = $firebase->getBooking($bookingId);

        if (
            ! is_string($uid)
            || ! is_array($profile)
            || ! in_array($profile['role'] ?? null, ['patient', 'midwife'], true)
            || (($profile['role'] ?? null) === 'midwife' && ($profile['verified'] ?? null) !== true)
            || $booking === null
        ) {
            return response()->json([
                'message' => 'Booking not found.',
                'code' => 'booking_not_found',
            ], 404);
        }

        $isMidwife = ($booking['midwife_id'] ?? null) === $uid
            && ($profile['role'] ?? null) === 'midwife';
        $isPatient = ($booking['patient_id'] ?? null) === $uid
            && ($profile['role'] ?? null) === 'patient';
        if (! $isMidwife && ! $isPatient) {
            return response()->json([
                'message' => 'Booking not found.',
                'code' => 'booking_not_found',
            ], 404);
        }

        $otherUid = $isMidwife
            ? ($booking['patient_id'] ?? null)
            : ($booking['midwife_id'] ?? null);
        $otherProfile = is_string($otherUid)
            ? $firebase->getUserProfile($otherUid)
            : null;

        return [$booking, $profile, $otherProfile ?? []];
    }

    /**
     * @param  array<string, mixed>  $booking
     * @param  array<string, mixed>  $currentProfile
     * @param  array<string, mixed>  $otherProfile
     * @return array<string, mixed>
     */
    private function publicBooking(
        string $id,
        array $booking,
        array $currentProfile,
        array $otherProfile,
    ): array {
        $currentIsMidwife = ($currentProfile['role'] ?? null) === 'midwife';

        return [
            'id' => $id,
            'patient_id' => $booking['patient_id'],
            'patient_name' => $currentIsMidwife
                ? ($otherProfile['name'] ?? 'Pasien')
                : ($currentProfile['name'] ?? 'Pasien'),
            'midwife_id' => $booking['midwife_id'],
            'midwife_name' => $currentIsMidwife
                ? ($currentProfile['name'] ?? 'Bidan')
                : ($otherProfile['name'] ?? 'Bidan'),
            'slot_id' => $booking['slot_id'] ?? '',
            'slot_start_at' => $booking['slot_start_at'],
            'complaint' => $booking['complaint'] ?? '',
            'amount' => $booking['amount'] ?? 0,
            'status' => $booking['status'],
            'payment_id' => $booking['payment_id'] ?? null,
            'rejection_reason' => $booking['rejection_reason'] ?? null,
            'consultation_started_at' => $booking['consultation_started_at'] ?? null,
            'ends_at' => $booking['ends_at'] ?? null,
            'consultation_completed_at' => $booking['consultation_completed_at'] ?? null,
            'created_at' => $booking['created_at'],
        ];
    }
}
