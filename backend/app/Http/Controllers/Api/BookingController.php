<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\BookingConfigurationException;
use App\Exceptions\MayarApiException;
use App\Exceptions\SlotUnavailableException;
use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use App\Services\MayarService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class BookingController extends Controller
{
    public function show(string $id, Request $request, FirebaseService $firebase): JsonResponse
    {
        $booking = $firebase->getBooking($id);
        $patientId = $request->attributes->get('firebase_uid');

        if ($booking === null || ($booking['patient_id'] ?? null) !== $patientId) {
            return response()->json([
                'message' => 'Booking not found.',
                'code' => 'booking_not_found',
            ], 404);
        }

        return response()->json(['data' => $booking]);
    }

    public function store(Request $request, FirebaseService $firebase): JsonResponse
    {
        $data = $request->validate([
            'slot_id' => ['required', 'string', 'max:256', 'not_regex:/\//'],
            'complaint' => ['required', 'string', 'max:1000'],
        ]);

        $patientId = $request->attributes->get('firebase_uid');
        $profile = $request->attributes->get('firebase_profile');

        if (! is_string($patientId) || ! is_array($profile)) {
            return response()->json([
                'message' => 'The patient profile is incomplete.',
                'code' => 'patient_profile_incomplete',
            ], 422);
        }

        try {
            $booking = $firebase->createBookingWithSlotHold(
                $patientId,
                $data['slot_id'],
                $data['complaint'],
            );
        } catch (SlotUnavailableException) {
            return response()->json([
                'message' => 'The selected slot is no longer available.',
                'code' => 'slot_unavailable',
            ], 409);
        } catch (BookingConfigurationException) {
            return response()->json([
                'message' => 'The midwife is not currently bookable.',
                'code' => 'booking_configuration_unavailable',
            ], 409);
        }

        return response()->json(['data' => $booking], 201);
    }

    public function checkout(
        string $id,
        Request $request,
        FirebaseService $firebase,
        MayarService $mayar,
    ): JsonResponse {
        $data = $request->validate([
            'mobile' => ['required', 'string', 'max:32'],
        ]);
        $patientId = $request->attributes->get('firebase_uid');
        $booking = $firebase->getBooking($id);

        if ($booking === null || ($booking['patient_id'] ?? null) !== $patientId) {
            return response()->json([
                'message' => 'Booking not found.',
                'code' => 'booking_not_found',
            ], 404);
        }

        if (($booking['status'] ?? null) !== 'awaiting_payment') {
            return response()->json([
                'message' => 'This booking is not awaiting payment.',
                'code' => 'booking_not_payable',
            ], 409);
        }

        if (! $this->isFutureTimestamp($booking['hold_expires_at'] ?? null)) {
            return response()->json([
                'message' => 'The booking payment hold has expired.',
                'code' => 'booking_hold_expired',
            ], 409);
        }

        if (
            is_string($booking['payment_id'] ?? null)
            && is_string($booking['checkout_url'] ?? null)
        ) {
            return response()->json(['data' => [
                'payment_id' => $booking['payment_id'],
                'checkout_url' => $booking['checkout_url'],
                'status' => 'pending',
            ]]);
        }

        if (! $mayar->isConfigured()) {
            return response()->json([
                'message' => 'Mayar is not configured on the server.',
                'code' => 'mayar_not_configured',
            ], 503);
        }

        $profile = $request->attributes->get('firebase_profile');
        $name = is_array($profile) ? ($profile['name'] ?? null) : null;
        $email = $request->attributes->get('firebase_email');

        if (
            ! is_string($name) || trim($name) === ''
            || ! is_string($email) || trim($email) === ''
        ) {
            return response()->json([
                'message' => 'The patient profile needs a name and email for checkout.',
                'code' => 'patient_profile_incomplete',
            ], 422);
        }

        $amount = $booking['amount'] ?? null;
        $holdExpiresAt = $booking['hold_expires_at'] ?? null;
        if (! is_int($amount) || ! is_string($holdExpiresAt)) {
            return response()->json([
                'message' => 'The booking is missing payment details.',
                'code' => 'booking_payment_data_invalid',
            ], 409);
        }

        try {
            $invoice = $mayar->createInvoice(
                trim($name),
                trim($email),
                $data['mobile'],
                $amount,
                $id,
                $holdExpiresAt,
            );
        } catch (MayarApiException $exception) {
            Log::warning('Mayar invoice creation failed.', [
                'booking_id' => $id,
                'failure_type' => $exception->failureType,
                'provider_status' => $exception->providerStatus,
            ]);

            [$message, $code, $status] = match ($exception->failureType) {
                'credentials' => [
                    'Mayar rejected the server API key or its permissions.',
                    'mayar_auth_failed',
                    503,
                ],
                'request_rejected' => [
                    'Mayar rejected the invoice data. Check the server logs for the provider status.',
                    'mayar_request_rejected',
                    502,
                ],
                'rate_limited' => [
                    'Mayar is rate-limiting invoice creation. Wait before retrying.',
                    'mayar_rate_limited',
                    503,
                ],
                'invalid_response' => [
                    'Mayar returned an unexpected invoice response.',
                    'mayar_invalid_response',
                    502,
                ],
                'tls_handshake' => [
                    'The backend could not establish a secure HTTPS connection to Mayar. Check the server network, VPN, proxy, or TLS inspection settings.',
                    'mayar_tls_error',
                    502,
                ],
                default => [
                    'Mayar could not be reached. Check the network and retry shortly.',
                    'mayar_unavailable',
                    502,
                ],
            };

            return response()->json([
                'message' => $message,
                'code' => $code,
                'provider_status' => $exception->providerStatus,
            ], $status);
        }

        if (! $firebase->attachMayarInvoice(
            $id,
            $patientId,
            $amount,
            $holdExpiresAt,
            $invoice,
        )) {
            $latestBooking = $firebase->getBooking($id);
            if (
                is_string($latestBooking['payment_id'] ?? null)
                && is_string($latestBooking['checkout_url'] ?? null)
            ) {
                return response()->json(['data' => [
                    'payment_id' => $latestBooking['payment_id'],
                    'checkout_url' => $latestBooking['checkout_url'],
                    'status' => 'pending',
                ]]);
            }

            Log::warning('Mayar invoice was created but the booking hold changed before it could be saved.', [
                'booking_id' => $id,
                'invoice_id' => $invoice['id'],
            ]);

            return response()->json([
                'message' => 'The booking hold changed before checkout could be started.',
                'code' => 'booking_hold_expired',
            ], 409);
        }

        return response()->json(['data' => [
            'payment_id' => $invoice['id'],
            'checkout_url' => $invoice['link'],
            'status' => 'pending',
        ]], 201);
    }

    private function isFutureTimestamp(mixed $timestamp): bool
    {
        $expiresAt = is_string($timestamp) ? strtotime($timestamp) : false;

        return $expiresAt !== false && $expiresAt > now('UTC')->getTimestamp();
    }
}
