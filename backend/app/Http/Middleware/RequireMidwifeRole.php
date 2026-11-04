<?php

namespace App\Http\Middleware;

use App\Services\FirebaseService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class RequireMidwifeRole
{
    public function __construct(private FirebaseService $firebase) {}

    /**
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $uid = $request->attributes->get('firebase_uid');
        if (! is_string($uid) || $uid === '') {
            return response()->json([
                'message' => 'A Firebase-authenticated user is required.',
                'code' => 'unauthenticated',
            ], 401);
        }

        $profile = $this->firebase->getUserProfile($uid);
        if (
            ($profile['role'] ?? null) !== 'midwife'
            || ($profile['verified'] ?? null) !== true
        ) {
            return response()->json([
                'message' => 'A verified midwife profile is required.',
                'code' => 'forbidden',
            ], 403);
        }

        $request->attributes->set('firebase_profile', $profile);

        return $next($request);
    }
}
