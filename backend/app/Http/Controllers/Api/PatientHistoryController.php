<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class PatientHistoryController extends Controller
{
    public function index(Request $request, FirebaseService $firebase): JsonResponse
    {
        $patientId = $request->attributes->get('firebase_uid');
        $patientProfile = $request->attributes->get('firebase_profile');
        $documents = $firebase->getBookingsForPatient($patientId);
        $midwifeNames = [];
        $data = [];
        $invalidCount = 0;

        foreach ($documents as $document) {
            $midwifeId = $document['midwife_id'] ?? null;
            if (
                ! is_string($document['id'] ?? null)
                || ! is_string($midwifeId)
                || ! is_string($document['slot_start_at'] ?? null)
                || ! is_string($document['status'] ?? null)
                || ! is_int($document['amount'] ?? null)
                || ! is_string($document['created_at'] ?? null)
            ) {
                $invalidCount++;

                continue;
            }

            if ($document['status'] === 'expired') {
                continue;
            }

            if (! array_key_exists($midwifeId, $midwifeNames)) {
                $midwifeProfile = $firebase->getUserProfile($midwifeId);
                $midwifeNames[$midwifeId] = is_string($midwifeProfile['name'] ?? null)
                    ? $midwifeProfile['name']
                    : 'Bidan';
            }

            $data[] = [
                'id' => $document['id'],
                'patient_id' => $patientId,
                'patient_name' => is_string($patientProfile['name'] ?? null)
                    ? $patientProfile['name']
                    : 'Pasien',
                'midwife_id' => $midwifeId,
                'midwife_name' => $midwifeNames[$midwifeId],
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
                'consultation_completed_at' => $document['consultation_completed_at'] ?? null,
                'created_at' => $document['created_at'],
            ];
        }

        if ($invalidCount > 0) {
            Log::warning('Firestore returned malformed patient booking documents.', [
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
}
