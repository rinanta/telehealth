<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\MidwifeController;
use App\Http\Middleware\RequirePatientRole;
use App\Http\Middleware\VerifyFirebaseIdToken;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Route;

Route::get('/health', static fn (): JsonResponse => response()->json([
    'status' => 'ok',
]))->name('health');

Route::middleware(VerifyFirebaseIdToken::class)->group(function (): void {
    Route::post('/auth/register', [AuthController::class, 'register'])->name('auth.register');
    Route::get('/me', [AuthController::class, 'me'])->name('auth.me');

    Route::middleware(RequirePatientRole::class)->group(function (): void {
        Route::get('/midwives', [MidwifeController::class, 'index'])->name('midwives.index');
        Route::get('/midwives/{id}/slots', [MidwifeController::class, 'slots'])->name('midwives.slots');
    });
});
