<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\BookingConfigurationException;
use App\Exceptions\SlotUnavailableException;
use App\Http\Controllers\Controller;
use App\Services\FirebaseService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

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
}
