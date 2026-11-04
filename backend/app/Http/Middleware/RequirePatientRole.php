<?php

namespace App\Http\Middleware;

use App\Services\FirebaseService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class RequirePatientRole
{
    public function __construct(private FirebaseService $firebase) {}

    /**
     * Handle an incoming request.
     *
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
        if (($profile['role'] ?? null) !== 'patient') {
            return response()->json([
                'message' => 'This endpoint is available to patients only.',
                'code' => 'forbidden',
            ], 403);
        }

        return $next($request);
    }
}
