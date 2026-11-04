<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\BookingConfigurationException;
use App\Exceptions\MidtransApiException;
use App\Exceptions\SlotUnavailableException;
use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use App\Services\MidtransService;
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
        MidtransService $midtrans,
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

        if (! $midtrans->isConfigured()) {
            return response()->json([
                'message' => 'Midtrans is not configured on the server.',
                'code' => 'payment_not_configured',
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
            $payment = $midtrans->createTransaction(
                trim($name),
                trim($email),
                $data['mobile'],
                $amount,
                $id,
                $holdExpiresAt,
            );
        } catch (MidtransApiException $exception) {
            Log::warning('Midtrans transaction creation failed.', [
                'booking_id' => $id,
                'failure_type' => $exception->failureType,
                'provider_status' => $exception->providerStatus,
            ]);

            [$message, $code, $status] = match ($exception->failureType) {
                'credentials' => [
                    'Midtrans rejected the server key. Check MIDTRANS_SERVER_KEY and MIDTRANS_ENVIRONMENT.',
                    'payment_auth_failed',
                    503,
                ],
                'request_rejected' => [
                    'Midtrans rejected the transaction data. Check the server logs for the provider status.',
                    'payment_request_rejected',
                    502,
                ],
                'rate_limited' => [
                    'Midtrans is rate-limiting transaction creation. Wait before retrying.',
                    'payment_rate_limited',
                    503,
                ],
                'invalid_response' => [
                    'Midtrans returned an unexpected transaction response.',
                    'payment_invalid_response',
                    502,
                ],
                'tls_handshake' => [
                    'The backend could not establish a secure HTTPS connection to Midtrans. Check the server network, VPN, proxy, or TLS inspection settings.',
                    'payment_tls_error',
                    502,
                ],
                default => [
                    'Midtrans could not be reached. Check the network and retry shortly.',
                    'payment_unavailable',
                    502,
                ],
            };

            return response()->json([
                'message' => $message,
                'code' => $code,
                'provider_status' => $exception->providerStatus,
            ], $status);
        }

        if (! $firebase->attachPaymentSession(
            $id,
            $patientId,
            $amount,
            $holdExpiresAt,
            $payment,
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

            Log::warning('Midtrans transaction was created but the booking hold changed before it could be saved.', [
                'booking_id' => $id,
                'order_id' => $payment['id'],
            ]);

            return response()->json([
                'message' => 'The booking hold changed before checkout could be started.',
                'code' => 'booking_hold_expired',
            ], 409);
        }

        return response()->json(['data' => [
            'payment_id' => $payment['id'],
            'checkout_url' => $payment['link'],
            'status' => 'pending',
        ]], 201);
    }

    private function isFutureTimestamp(mixed $timestamp): bool
    {
        $expiresAt = is_string($timestamp) ? strtotime($timestamp) : false;

        return $expiresAt !== false && $expiresAt > now('UTC')->getTimestamp();
    }
}
