<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ConsultationResultController extends Controller
{
    public function show(
        string $id,
        Request $request,
        FirebaseService $firebase,
    ): JsonResponse {
        $uid = $request->attributes->get('firebase_uid');
        $profile = $request->attributes->get('firebase_profile')
            ?? (is_string($uid) ? $firebase->getUserProfile($uid) : null);
        $booking = $firebase->getBooking($id);

        $role = is_array($profile) ? ($profile['role'] ?? null) : null;
        $isParticipant = is_string($uid)
            && $booking !== null
            && (
                ($role === 'patient' && ($booking['patient_id'] ?? null) === $uid)
                || (
                    $role === 'midwife'
                    && ($profile['verified'] ?? null) === true
                    && ($booking['midwife_id'] ?? null) === $uid
                )
            );

        if (! $isParticipant) {
            return response()->json([
                'message' => 'Booking not found.',
                'code' => 'booking_not_found',
            ], 404);
        }

        $consultationResult = ($booking['status'] ?? null) === 'completed'
            ? $firebase->getConsultationResult($id)
            : null;

        if ($consultationResult === null) {
            return response()->json([
                'message' => 'The consultation result is not available yet.',
                'code' => 'result_not_found',
            ], 404);
        }

        return response()->json(['data' => [
            'id' => $id,
            'consultation_id' => $consultationResult['consultation_id'] ?? $id,
            'booking_id' => $id,
            'patient_name' => $consultationResult['patient_name'] ?? 'Pasien',
            'midwife_name' => $consultationResult['midwife_name'] ?? 'Bidan',
            'summary' => $consultationResult['summary'] ?? '',
            'advice' => $consultationResult['advice'] ?? '',
            'supplement_note' => $consultationResult['supplement_note'] ?? null,
            'follow_up' => $consultationResult['follow_up'] ?? '',
            'saved_by' => $consultationResult['saved_by'] ?? ($consultationResult['midwife_name'] ?? 'Bidan'),
            'completed_at' => $consultationResult['completed_at']
                ?? ($booking['consultation_completed_at'] ?? now('UTC')->toIso8601String()),
        ]]);
    }
}
