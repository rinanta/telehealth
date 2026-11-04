<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MidwifeProfileController extends Controller
{
    /**
     * GET /api/midwife/profile — kembalikan profil dan tarif bidan yang sedang login.
     */
    public function show(Request $request, FirebaseService $firebase): JsonResponse
    {
        $uid = $request->attributes->get('firebase_uid');
        $midwife = $firebase->getMidwifeProfile($uid);

        if ($midwife === null) {
            return response()->json([
                'message' => 'Midwife profile not found.',
                'code' => 'midwife_not_found',
            ], 404);
        }

        return response()->json(['data' => $this->formatProfile($midwife, $uid)]);
    }

    /**
     * PATCH /api/midwife/profile — perbarui tarif dan/atau bio bidan.
     * Hanya field yang dikirim yang diubah; `verified`, `role`, `active`, dan
     * `verification_status` tidak dapat diubah melalui endpoint ini.
     */
    public function update(Request $request, FirebaseService $firebase): JsonResponse
    {
        $data = $request->validate([
            'consultation_fee' => ['sometimes', 'required', 'integer', 'min:1000', 'max:10000000'],
            'bio' => ['sometimes', 'nullable', 'string', 'max:500'],
            'display_name' => ['sometimes', 'required', 'string', 'max:120'],
        ]);

        if (empty($data)) {
            return response()->json([
                'message' => 'No updatable fields provided.',
                'code' => 'nothing_to_update',
            ], 422);
        }

        $uid = $request->attributes->get('firebase_uid');
        $result = $firebase->updateMidwifeProfile($uid, $data);

        if ($result === 'not_found') {
            return response()->json([
                'message' => 'Midwife profile not found.',
                'code' => 'midwife_not_found',
            ], 404);
        }

        $midwife = $firebase->getMidwifeProfile($uid);

        return response()->json(['data' => $this->formatProfile($midwife ?? [], $uid)]);
    }

    /**
     * @param  array<string, mixed>  $midwife
     * @return array<string, mixed>
     */
    private function formatProfile(array $midwife, string $uid): array
    {
        return [
            'uid' => $uid,
            'display_name' => $midwife['display_name'] ?? null,
            'credential_label' => $midwife['credential_label'] ?? null,
            'bio' => is_string($midwife['bio'] ?? null) ? $midwife['bio'] : null,
            'consultation_fee' => is_int($midwife['consultation_fee'] ?? null) && $midwife['consultation_fee'] > 0
                ? $midwife['consultation_fee']
                : null,
            'active' => $midwife['active'] ?? false,
            'verification_status' => $midwife['verification_status'] ?? 'pending_verification',
        ];
    }
}
