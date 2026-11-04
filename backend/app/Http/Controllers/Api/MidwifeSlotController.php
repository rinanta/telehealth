<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class MidwifeSlotController extends Controller
{
    /**
     * GET /api/midwife/slots — daftar semua slot milik bidan (semua status).
     */
    public function index(Request $request, FirebaseService $firebase): JsonResponse
    {
        $midwifeId = $request->attributes->get('firebase_uid');
        $documents = $firebase->getSlotsForMidwife($midwifeId);
        $data = [];
        $invalidCount = 0;

        foreach ($documents as $document) {
            if (! $this->isValidSlotDocument($document)) {
                $invalidCount++;

                continue;
            }

            $data[] = $this->formatSlot($document);
        }

        if ($invalidCount > 0) {
            Log::warning('Firestore returned malformed slot documents.', [
                'collection' => 'slots',
                'invalid_count' => $invalidCount,
                'midwife_id' => $midwifeId,
            ]);
        }

        usort(
            $data,
            static fn (array $a, array $b): int => strcmp($a['start_at'], $b['start_at']),
        );

        return response()->json(['data' => $data]);
    }

    /**
     * POST /api/midwife/slots — buat slot baru milik bidan.
     * Durasi wajib 30 menit; slot tidak boleh di masa lalu.
     */
    public function store(Request $request, FirebaseService $firebase): JsonResponse
    {
        $data = $request->validate([
            'start_at' => ['required', 'date', 'after:now'],
        ]);

        $startAt = date('Y-m-d\TH:i:s\Z', strtotime($data['start_at']));
        $endAt = date('Y-m-d\TH:i:s\Z', strtotime($startAt) + 1800); // tepat 30 menit

        $midwifeId = $request->attributes->get('firebase_uid');
        $result = $firebase->createSlotForMidwife($midwifeId, $startAt, $endAt);

        if ($result === 'overlap') {
            return response()->json([
                'message' => 'The requested time slot overlaps with an existing slot.',
                'code' => 'slot_overlap',
            ], 409);
        }

        return response()->json(['data' => $result], 201);
    }

    /**
     * PATCH /api/midwife/slots/{id} — pindahkan jadwal slot (hanya jika masih `available`).
     */
    public function update(string $id, Request $request, FirebaseService $firebase): JsonResponse
    {
        $data = $request->validate([
            'start_at' => ['required', 'date', 'after:now'],
        ]);

        $startAt = date('Y-m-d\TH:i:s\Z', strtotime($data['start_at']));
        $endAt = date('Y-m-d\TH:i:s\Z', strtotime($startAt) + 1800);

        $midwifeId = $request->attributes->get('firebase_uid');
        $result = $firebase->updateSlotForMidwife($midwifeId, $id, $startAt, $endAt);

        if ($result === 'not_found' || $result === 'not_owned') {
            return response()->json([
                'message' => 'Slot not found.',
                'code' => 'slot_not_found',
            ], 404);
        }

        if ($result === 'not_available') {
            return response()->json([
                'message' => 'Only available slots can be rescheduled. This slot is held or already booked.',
                'code' => 'slot_not_available',
            ], 409);
        }

        if ($result === 'overlap') {
            return response()->json([
                'message' => 'The requested time slot overlaps with an existing slot.',
                'code' => 'slot_overlap',
            ], 409);
        }

        return response()->json(['data' => $result]);
    }

    /**
     * DELETE /api/midwife/slots/{id} — hapus slot (hanya jika masih `available`).
     */
    public function destroy(string $id, Request $request, FirebaseService $firebase): JsonResponse
    {
        $midwifeId = $request->attributes->get('firebase_uid');
        $result = $firebase->deleteSlotForMidwife($midwifeId, $id);

        if ($result === 'not_found' || $result === 'not_owned') {
            return response()->json([
                'message' => 'Slot not found.',
                'code' => 'slot_not_found',
            ], 404);
        }

        if ($result === 'not_available') {
            return response()->json([
                'message' => 'Only available slots can be deleted. This slot is held or already booked.',
                'code' => 'slot_not_available',
            ], 409);
        }

        return response()->json(['data' => ['id' => $id, 'deleted' => true]]);
    }

    /**
     * @param  array<string, mixed>  $document
     */
    private function isValidSlotDocument(array $document): bool
    {
        return is_string($document['id'] ?? null)
            && is_string($document['start_at'] ?? null)
            && is_string($document['end_at'] ?? null)
            && is_string($document['status'] ?? null);
    }

    /**
     * @param  array<string, mixed>  $document
     * @return array<string, mixed>
     */
    private function formatSlot(array $document): array
    {
        return [
            'id' => $document['id'],
            'midwife_id' => $document['midwife_id'] ?? null,
            'start_at' => $document['start_at'],
            'end_at' => $document['end_at'],
            'status' => $document['status'],
        ];
    }
}
