<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BookingController;
use App\Http\Controllers\Api\MayarWebhookController;
use App\Http\Controllers\Api\MidwifeBookingController;
use App\Http\Controllers\Api\MidwifeController;
use App\Http\Middleware\RequireMidwifeRole;
use App\Http\Middleware\RequirePatientRole;
use App\Http\Middleware\VerifyFirebaseIdToken;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Route;

Route::get('/health', static fn (): JsonResponse => response()->json([
    'status' => 'ok',
]))->name('health');

Route::post('/webhooks/mayar/{secret}', [MayarWebhookController::class, 'handle'])
    ->middleware('throttle:10,1')
    ->name('webhooks.mayar');

Route::middleware(VerifyFirebaseIdToken::class)->group(function (): void {
    Route::post('/auth/register', [AuthController::class, 'register'])->name('auth.register');
    Route::get('/me', [AuthController::class, 'me'])->name('auth.me');

    Route::middleware(RequirePatientRole::class)->group(function (): void {
        Route::get('/midwives', [MidwifeController::class, 'index'])->name('midwives.index');
        Route::get('/midwives/{id}/slots', [MidwifeController::class, 'slots'])->name('midwives.slots');
        Route::get('/bookings/{id}', [BookingController::class, 'show'])->name('bookings.show');
        Route::post('/bookings', [BookingController::class, 'store'])
            ->middleware('throttle:10,1')
            ->name('bookings.store');
        Route::post('/bookings/{id}/checkout', [BookingController::class, 'checkout'])
            ->middleware('throttle:5,1')
            ->name('bookings.checkout');
    });

    Route::middleware(RequireMidwifeRole::class)->prefix('midwife')->group(function (): void {
        Route::get('/bookings', [MidwifeBookingController::class, 'index'])
            ->name('midwife.bookings.index');
    });

    Route::middleware(RequireMidwifeRole::class)->group(function (): void {
        Route::post('/bookings/{id}/accept', [MidwifeBookingController::class, 'accept'])
            ->name('midwife.bookings.accept');
        Route::post('/bookings/{id}/reject', [MidwifeBookingController::class, 'reject'])
            ->name('midwife.bookings.reject');
    });
});
