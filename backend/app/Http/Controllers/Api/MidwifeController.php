<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Log;

class MidwifeController extends Controller
{
    public function index(FirebaseService $firebase): JsonResponse
    {
        $documents = $firebase->getActiveVerifiedMidwives();
        $data = [];
        $invalidCount = 0;

        foreach ($documents as $document) {
            if (! $this->isEligibleMidwife($document)) {
                $invalidCount++;
                Log::warning('Midwife omitted from catalog because its document is incomplete or inactive.', [
                    'midwife_id' => $document['id'] ?? null,
                    'active' => $document['active'] ?? null,
                    'verification_status' => $document['verification_status'] ?? null,
                    'has_display_name' => is_string($document['display_name'] ?? null),
                    'has_credential_label' => is_string($document['credential_label'] ?? null),
                ]);

                continue;
            }

            $data[] = [
                'uid' => $document['id'],
                'display_name' => $document['display_name'],
                'credential_label' => $document['credential_label'],
                'bio' => is_string($document['bio'] ?? null) ? $document['bio'] : null,
                'price' => is_int($document['consultation_fee'] ?? null)
                    && $document['consultation_fee'] > 0
                    ? $document['consultation_fee']
                    : null,
            ];
        }

        if ($invalidCount > 0) {
            Log::warning('Firestore returned malformed midwife catalog documents.', [
                'collection' => 'midwives',
                'invalid_count' => $invalidCount,
            ]);
        }

        return response()->json(['data' => $data]);
    }

    public function slots(string $id, FirebaseService $firebase): JsonResponse
    {
        $midwife = collect($firebase->getActiveVerifiedMidwives())
            ->first(fn (array $document): bool => $this->isEligibleMidwife($document)
                && $document['id'] === $id);

        if ($midwife === null) {
            return response()->json([
                'message' => 'Midwife not found.',
                'code' => 'midwife_not_found',
            ], 404);
        }

        $documents = $firebase->getAvailableSlots($id);
        $data = [];
        $invalidCount = 0;

        foreach ($documents as $document) {
            if (! $this->isValidAvailableSlot($document, $id)) {
                $invalidCount++;

                continue;
            }

            $data[] = [
                'id' => $document['id'],
                'midwife_id' => $document['midwife_id'],
                'start_at' => $document['start_at'],
                'end_at' => $document['end_at'],
                'status' => 'available',
            ];
        }

        if ($invalidCount > 0) {
            Log::warning('Firestore returned malformed available slot documents.', [
                'collection' => 'slots',
                'invalid_count' => $invalidCount,
            ]);
        }

        return response()->json(['data' => $data]);
    }

    /**
     * @param  array<string, mixed>  $document
     */
    private function isEligibleMidwife(array $document): bool
    {
        return is_string($document['id'] ?? null)
            && is_string($document['display_name'] ?? null)
            && $document['display_name'] !== ''
            && is_string($document['credential_label'] ?? null)
            && $document['credential_label'] !== ''
            && ($document['active'] ?? null) === true
            && ($document['verification_status'] ?? null) === 'verified';
    }

    /**
     * @param  array<string, mixed>  $document
     */
    private function isValidAvailableSlot(array $document, string $midwifeId): bool
    {
        $startAt = $document['start_at'] ?? null;
        $endAt = $document['end_at'] ?? null;
        $startTimestamp = is_string($startAt) ? strtotime($startAt) : false;
        $endTimestamp = is_string($endAt) ? strtotime($endAt) : false;

        return is_string($document['id'] ?? null)
            && ($document['midwife_id'] ?? null) === $midwifeId
            && ($document['status'] ?? null) === 'available'
            && empty($document['hold_booking_id'])
            && $startTimestamp !== false
            && $endTimestamp !== false
            && $startTimestamp > now()->getTimestamp()
            && $endTimestamp - $startTimestamp === 1800;
    }
}
