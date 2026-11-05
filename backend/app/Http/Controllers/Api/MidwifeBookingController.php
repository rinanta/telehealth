<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class MidwifeBookingController extends Controller
{
    public function index(Request $request, FirebaseService $firebase): JsonResponse
    {
        $midwifeId = $request->attributes->get('firebase_uid');
        $midwifeProfile = $request->attributes->get('firebase_profile');
        $documents = $firebase->getBookingsForMidwife($midwifeId);
        $data = [];
        $invalidCount = 0;

        foreach ($documents as $document) {
            $patientId = $document['patient_id'] ?? null;
            if (
                ! is_string($document['id'] ?? null)
                || ! is_string($patientId)
                || ! is_string($document['slot_start_at'] ?? null)
                || ! is_string($document['status'] ?? null)
                || ! is_int($document['amount'] ?? null)
                || ! is_string($document['created_at'] ?? null)
            ) {
                $invalidCount++;

                continue;
            }

            $patient = $firebase->getUserProfile($patientId);
            $data[] = [
                'id' => $document['id'],
                'patient_id' => $patientId,
                'patient_name' => is_string($patient['name'] ?? null)
                    ? $patient['name']
                    : 'Pasien',
                'midwife_id' => $midwifeId,
                'midwife_name' => is_string($midwifeProfile['name'] ?? null)
                    ? $midwifeProfile['name']
                    : 'Bidan',
                'slot_id' => is_string($document['slot_id'] ?? null)
                    ? $document['slot_id']
                    : '',
                'slot_start_at' => $document['slot_start_at'],
                'complaint' => is_string($document['complaint'] ?? null)
                    ? $document['complaint']
                    : '',
                'amount' => $document['amount'],
                'status' => $document['status'],
                'payment_id' => is_string($document['payment_id'] ?? null)
                    ? $document['payment_id']
                    : null,
                'rejection_reason' => is_string($document['rejection_reason'] ?? null)
                    ? $document['rejection_reason']
                    : null,
                'consultation_started_at' => $document['consultation_started_at'] ?? null,
                'ends_at' => $document['ends_at'] ?? null,
                'consultation_completed_at' => $document['consultation_completed_at'] ?? null,
                'created_at' => $document['created_at'],
            ];
        }

        if ($invalidCount > 0) {
            Log::warning('Firestore returned malformed midwife booking documents.', [
                'collection' => 'bookings',
                'invalid_count' => $invalidCount,
            ]);
        }

        usort(
            $data,
            static fn (array $left, array $right): int => strcmp(
                $right['created_at'],
                $left['created_at'],
            ),
        );

        return response()->json(['data' => $data]);
    }

    public function accept(
        string $id,
        Request $request,
        FirebaseService $firebase,
    ): JsonResponse {
        $result = $firebase->acceptBookingForMidwife(
            $id,
            $request->attributes->get('firebase_uid'),
        );

        if (in_array($result, ['not_found', 'not_owned'], true)) {
            return response()->json([
                'message' => 'Booking not found.',
                'code' => 'booking_not_found',
            ], 404);
        }

        if ($result === 'no_show') {
            return response()->json([
                'message' => 'This booking is past the 10-minute start window and was marked as no-show.',
                'code' => 'booking_no_show',
            ], 409);
        }

        if ($result !== 'accepted') {
            return response()->json([
                'message' => 'This booking is no longer waiting for confirmation.',
                'code' => 'booking_not_actionable',
            ], 409);
        }

        return response()->json(['data' => ['id' => $id, 'status' => 'confirmed']]);
    }

    public function reject(
        string $id,
        Request $request,
        FirebaseService $firebase,
    ): JsonResponse {
        $data = $request->validate([
            'reason' => ['required', 'string', 'min:5', 'max:500'],
        ]);
        $result = $firebase->rejectBookingForMidwife(
            $id,
            $request->attributes->get('firebase_uid'),
            trim($data['reason']),
        );

        if (in_array($result, ['not_found', 'not_owned'], true)) {
            return response()->json([
                'message' => 'Booking not found.',
                'code' => 'booking_not_found',
            ], 404);
        }

        if ($result !== 'rejected') {
            return response()->json([
                'message' => 'This booking is no longer waiting for confirmation.',
                'code' => 'booking_not_actionable',
            ], 409);
        }

        return response()->json(['data' => [
            'id' => $id,
            'status' => 'rejected',
            'refund_required' => true,
        ]]);
    }

    public function start(
        string $id,
        Request $request,
        FirebaseService $firebase,
    ): JsonResponse {
        $result = $firebase->startConsultationForMidwife(
            $id,
            $request->attributes->get('firebase_uid'),
        );

        if (in_array($result, ['not_found', 'not_owned'], true)) {
            return response()->json([
                'message' => 'Booking not found.',
                'code' => 'booking_not_found',
            ], 404);
        }

        if ($result === 'not_ready') {
            return response()->json([
                'message' => 'The consultation can only start at or after its scheduled time.',
                'code' => 'consultation_not_due',
            ], 409);
        }

        if ($result === 'no_show') {
            return response()->json([
                'message' => 'This booking is past the 10-minute start window and cannot be started.',
                'code' => 'booking_no_show',
            ], 409);
        }

        if ($result === 'invalid_schedule') {
            return response()->json([
                'message' => 'The booking has an invalid scheduled time.',
                'code' => 'invalid_booking_schedule',
            ], 409);
        }

        if ($result !== 'started') {
            return response()->json([
                'message' => 'This booking is not ready to start.',
                'code' => 'booking_not_actionable',
            ], 409);
        }

        $now = now('UTC');
        $startedAt = $now->toIso8601String();
        $endsAt = $now->copy()->addMinutes(30)->toIso8601String();

        return response()->json(['data' => [
            'id' => $id,
            'status' => 'active',
            'consultation_started_at' => $startedAt,
            'ends_at' => $endsAt,
        ]]);
    }

    public function complete(
        string $id,
        Request $request,
        FirebaseService $firebase,
    ): JsonResponse {
        $data = $request->validate([
            'summary' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'advice' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'supplement_note' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'follow_up' => ['sometimes', 'nullable', 'string', 'max:5000'],
        ]);

        foreach (['summary', 'advice', 'follow_up'] as $field) {
            if (! array_key_exists($field, $data)) {
                $data[$field] = null;
            }
        }
        $midwifeProfile = $request->attributes->get('firebase_profile');
        $midwifeName = is_string($midwifeProfile['name'] ?? null)
            ? $midwifeProfile['name']
            : 'Bidan';
        $supplementNote = isset($data['supplement_note'])
            ? trim($data['supplement_note'])
            : null;

        $outcome = $firebase->completeConsultationForMidwife(
            $id,
            $request->attributes->get('firebase_uid'),
            $midwifeName,
            [
                'summary' => trim($data['summary'] ?? ''),
                'advice' => trim($data['advice'] ?? ''),
                'supplement_note' => $supplementNote === '' ? null : $supplementNote,
                'follow_up' => trim($data['follow_up'] ?? ''),
            ],
        );

        if (! is_string($outcome['result'] ?? null)) {
            return response()->json([
                'message' => 'Invalid consultation result request.',
                'code' => 'invalid_result_request',
            ], 422);
        }

        if (in_array($outcome['result'], ['not_found', 'not_owned'], true)) {
            return response()->json([
                'message' => 'Booking not found.',
                'code' => 'booking_not_found',
            ], 404);
        }

        if ($outcome['result'] !== 'completed') {
            return response()->json([
                'message' => 'This consultation is not active, so it cannot be completed.',
                'code' => 'booking_not_actionable',
            ], 409);
        }

        return response()->json(['data' => [
            'id' => $id,
            'status' => 'completed',
            'consultation_completed_at' => $outcome['consultation_completed_at'],
            'result' => $outcome['consultation_result'],
        ]]);
    }
}
