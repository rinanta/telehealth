<?php

use App\Http\Controllers\Api\AiChatController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BookingController;
use App\Http\Controllers\Api\ConsultationChatController;
use App\Http\Controllers\Api\ConsultationResultController;
use App\Http\Controllers\Api\MidtransWebhookController;
use App\Http\Controllers\Api\MidwifeBookingController;
use App\Http\Controllers\Api\MidwifeController;
use App\Http\Controllers\Api\MidwifeProfileController;
use App\Http\Controllers\Api\MidwifeSlotController;
use App\Http\Controllers\Api\PatientHistoryController;
use App\Http\Middleware\RequireMidwifeRole;
use App\Http\Middleware\RequirePatientRole;
use App\Http\Middleware\VerifyFirebaseIdToken;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Route;

Route::get('/health', static fn (): JsonResponse => response()->json([
    'status' => 'ok',
]))->name('health');

Route::post('/webhooks/midtrans', [MidtransWebhookController::class, 'handle'])
    ->middleware('throttle:60,1')
    ->name('webhooks.midtrans');

Route::middleware(VerifyFirebaseIdToken::class)->group(function (): void {
    Route::post('/auth/register', [AuthController::class, 'register'])->name('auth.register');
    Route::get('/me', [AuthController::class, 'me'])->name('auth.me');
    Route::post('/ai/chat', [AiChatController::class, 'store'])
        ->middleware('throttle:15,1')
        ->name('ai.chat.store');

    Route::middleware(RequirePatientRole::class)->group(function (): void {
        Route::get('/midwives', [MidwifeController::class, 'index'])->name('midwives.index');
        Route::get('/midwives/{id}/slots', [MidwifeController::class, 'slots'])->name('midwives.slots');
        Route::get('/history', [PatientHistoryController::class, 'index'])->name('history.index');
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
        Route::get('/profile', [MidwifeProfileController::class, 'show'])
            ->name('midwife.profile.show');
        Route::patch('/profile', [MidwifeProfileController::class, 'update'])
            ->name('midwife.profile.update');
        Route::get('/slots', [MidwifeSlotController::class, 'index'])
            ->name('midwife.slots.index');
        Route::post('/slots', [MidwifeSlotController::class, 'store'])
            ->name('midwife.slots.store');
        Route::patch('/slots/{id}', [MidwifeSlotController::class, 'update'])
            ->name('midwife.slots.update');
        Route::delete('/slots/{id}', [MidwifeSlotController::class, 'destroy'])
            ->name('midwife.slots.destroy');
    });

    Route::middleware(RequireMidwifeRole::class)->group(function (): void {
        Route::post('/bookings/{id}/accept', [MidwifeBookingController::class, 'accept'])
            ->name('midwife.bookings.accept');
        Route::post('/bookings/{id}/reject', [MidwifeBookingController::class, 'reject'])
            ->name('midwife.bookings.reject');
        Route::post('/bookings/{id}/start', [MidwifeBookingController::class, 'start'])
            ->name('midwife.bookings.start');
        Route::post('/bookings/{id}/complete', [MidwifeBookingController::class, 'complete'])
            ->name('midwife.bookings.complete');
    });

    Route::get('/bookings/{id}/messages', [ConsultationChatController::class, 'index'])
        ->name('bookings.messages.index');
    Route::post('/bookings/{id}/messages', [ConsultationChatController::class, 'store'])
        ->name('bookings.messages.store');
    Route::get('/bookings/{id}/result', [ConsultationResultController::class, 'show'])
        ->name('bookings.result.show');
});
