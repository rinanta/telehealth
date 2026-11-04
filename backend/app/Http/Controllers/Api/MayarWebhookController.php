<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\MayarApiException;
use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use App\Services\MayarService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class MayarWebhookController extends Controller
{
    public function handle(
        string $secret,
        Request $request,
        FirebaseService $firebase,
        MayarService $mayar,
    ): JsonResponse {
        $configuredSecret = config('services.mayar.webhook_secret');
        if (
            ! is_string($configuredSecret)
            || $configuredSecret === ''
            || ! hash_equals($configuredSecret, $secret)
        ) {
            abort(404);
        }

        $event = $request->input('event');
        if (is_array($event)) {
            $event = $event['received'] ?? null;
        }
        if (! is_string($event)) {
            $event = $request->input('event.received');
        }

        if ($event !== 'payment.received') {
            return response()->json(['status' => 'ignored']);
        }

        if (! $mayar->isConfigured()) {
            return response()->json([
                'message' => 'Mayar is not configured on the server.',
                'code' => 'mayar_not_configured',
            ], 503);
        }

        try {
            $processed = 0;
            foreach ($firebase->getPendingMayarPayments() as $payment) {
                $invoiceId = $payment['invoice_id'] ?? null;
                if (! is_string($invoiceId) || $invoiceId === '') {
                    continue;
                }

                $invoice = $mayar->getInvoice($invoiceId);
                if (($invoice['status'] ?? null) !== 'paid') {
                    continue;
                }

                $result = $firebase->completeMayarPayment($invoiceId, $invoice);
                if ($result === 'reconciliation_required') {
                    Log::warning('Paid Mayar invoice needs manual reconciliation.', [
                        'invoice_id' => $invoiceId,
                    ]);
                } elseif ($result === 'retry') {
                    return response()->json([
                        'message' => 'Payment verification will be retried.',
                        'code' => 'payment_update_conflict',
                    ], 503);
                } elseif ($result === 'paid') {
                    $processed++;
                }
            }
        } catch (MayarApiException $exception) {
            Log::warning('Mayar webhook invoice verification failed.', [
                'exception' => $exception::class,
            ]);

            return response()->json([
                'message' => 'Payment verification is temporarily unavailable.',
                'code' => 'mayar_unavailable',
            ], 503);
        }

        return response()->json([
            'status' => 'processed',
            'payments_verified' => $processed,
        ]);
    }
}
