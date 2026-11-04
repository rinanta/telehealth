<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AuthController extends Controller
{
    public function register(Request $request, FirebaseService $firebase): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'role' => ['required', 'in:patient,midwife'],
            'credential_label' => ['required_if:role,midwife', 'string', 'max:120'],
            'str_number' => ['required_if:role,midwife', 'string', 'max:80'],
        ]);

        $uid = $request->attributes->get('firebase_uid');
        $email = $request->attributes->get('firebase_email');

        if (! is_string($uid) || ! is_string($email) || $email === '') {
            return response()->json([
                'message' => 'A Firebase-authenticated email address is required to register.',
                'code' => 'email_required',
            ], 422);
        }

        $role = $data['role'];
        $profile = [
            'uid' => $uid,
            'name' => $data['name'],
            'email' => $email,
            'role' => $role,
            'verified' => $role === 'patient',
            'created_at' => now()->toIso8601String(),
        ];

        if ($role === 'midwife') {
            $profile['credential_label'] = $data['credential_label'];
            $profile['str_number'] = $data['str_number'];
        }

        if (! $firebase->createUserProfile($uid, $profile)) {
            return response()->json([
                'message' => 'A profile already exists for this Firebase user.',
                'code' => 'profile_already_exists',
            ], 409);
        }

        return response()->json([
            'data' => $this->publicProfile($profile),
        ], 201);
    }

    public function me(Request $request, FirebaseService $firebase): JsonResponse
    {
        $uid = $request->attributes->get('firebase_uid');
        $profile = $firebase->getUserProfile($uid);

        if ($profile === null) {
            return response()->json([
                'message' => 'No TeleBunda profile exists for this Firebase user.',
                'code' => 'profile_not_found',
            ], 404);
        }

        return response()->json([
            'data' => $this->publicProfile($profile),
        ]);
    }

    /**
     * @param  array<string, mixed>  $profile
     * @return array<string, mixed>
     */
    private function publicProfile(array $profile): array
    {
        unset($profile['str_number']);

        return $profile;
    }
}
