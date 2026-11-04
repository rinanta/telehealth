<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\MidtransApiException;
use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use App\Services\MidtransService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class MidtransWebhookController extends Controller
{
    public function handle(
        Request $request,
        FirebaseService $firebase,
        MidtransService $midtrans,
    ): JsonResponse {
        if (! $midtrans->isConfigured()) {
            return response()->json([
                'message' => 'Midtrans is not configured on the server.',
                'code' => 'payment_not_configured',
            ], 503);
        }

        $orderId = $request->input('order_id');
        $statusCode = $request->input('status_code');
        $grossAmount = $request->input('gross_amount');
        $signature = $request->input('signature_key');

        if (
            ! is_string($orderId) || $orderId === ''
            || ! is_string($statusCode)
            || ! is_string($grossAmount)
            || ! is_string($signature)
        ) {
            return response()->json([
                'message' => 'The notification payload is incomplete.',
                'code' => 'invalid_notification',
            ], 400);
        }

        // Authenticity check #1: the shared-secret signature.
        if (! $midtrans->hasValidNotificationSignature(
            $orderId,
            $statusCode,
            $grossAmount,
            $signature,
        )) {
            return response()->json([
                'message' => 'The notification signature is invalid.',
                'code' => 'invalid_signature',
            ], 403);
        }

        try {
            // Authenticity check #2: never trust the callback body for the
            // status or amount; ask Midtrans directly.
            $status = $midtrans->getStatus($orderId);
        } catch (MidtransApiException $exception) {
            Log::warning('Midtrans webhook status verification failed.', [
                'order_id' => $orderId,
                'failure_type' => $exception->failureType,
                'provider_status' => $exception->providerStatus,
            ]);

            return response()->json([
                'message' => 'Payment verification is temporarily unavailable.',
                'code' => 'payment_unavailable',
            ], 503);
        }

        if ($status['status'] !== 'paid') {
            return response()->json([
                'status' => 'ignored',
                'transaction_status' => $status['transaction_status'],
            ]);
        }

        $result = $firebase->completePayment($orderId, $status);

        if ($result === 'retry') {
            return response()->json([
                'message' => 'Payment verification will be retried.',
                'code' => 'payment_update_conflict',
            ], 503);
        }

        if ($result === 'reconciliation_required') {
            Log::warning('Paid Midtrans order needs manual reconciliation.', [
                'order_id' => $orderId,
            ]);
        }

        return response()->json([
            'status' => 'processed',
            'payments_verified' => $result === 'paid' ? 1 : 0,
        ]);
    }
}
