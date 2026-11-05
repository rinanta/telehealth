<?php

namespace App\Http\Middleware;

use App\Services\FirebaseService;
use Closure;
use Illuminate\Http\Request;
use Kreait\Firebase\JWT\Error\FetchingGooglePublicKeysFailed;
use Kreait\Firebase\JWT\Error\IdTokenVerificationFailed;
use Symfony\Component\HttpFoundation\Response;

class VerifyFirebaseIdToken
{
    public function handle(Request $request, Closure $next): Response
    {
        $token = $request->bearerToken();

        if (! is_string($token) || $token === '') {
            return response()->json([
                'message' => 'Firebase ID token is required.',
                'code' => 'unauthenticated',
            ], 401);
        }

        $firebase = app(FirebaseService::class);

        if (! $firebase->isConfigured()) {
            return response()->json([
                'message' => 'Firebase server credentials are not configured.',
                'code' => 'firebase_not_configured',
            ], 503);
        }

        try {
            $claims = $firebase->verifyIdToken($token);
        } catch (IdTokenVerificationFailed $error) {
            report($error);

            return response()->json([
                'message' => 'Firebase ID token is invalid or expired.',
                'code' => 'unauthenticated',
            ], 401);
        } catch (FetchingGooglePublicKeysFailed) {
            return response()->json([
                'message' => 'Firebase token verification is temporarily unavailable.',
                'code' => 'firebase_unavailable',
            ], 503);
        }

        $uid = $claims['sub'] ?? null;

        if (! is_string($uid) || $uid === '') {
            return response()->json([
                'message' => 'Firebase ID token does not contain a valid user ID.',
                'code' => 'unauthenticated',
            ], 401);
        }

        $request->attributes->set('firebase_uid', $uid);
        $request->attributes->set('firebase_email', $claims['email'] ?? null);

        return $next($request);
    }
}
