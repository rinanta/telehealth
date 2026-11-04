<?php

namespace Tests\Feature;

use App\Services\FirebaseService;
use Mockery;
use Tests\TestCase;

class BookingExpiryCommandTest extends TestCase
{
    public function test_expiry_command_releases_each_expired_booking_hold(): void
    {
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('getExpiredBookingHolds')
            ->once()
            ->andReturn([
                ['id' => 'booking-expired'],
                ['id' => null],
                ['id' => 'booking-raced'],
            ]);
        $firebase->shouldReceive('expireBookingHold')
            ->once()
            ->with('booking-expired')
            ->andReturn(true);
        $firebase->shouldReceive('expireBookingHold')
            ->once()
            ->with('booking-raced')
            ->andReturn(false);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->artisan('bookings:expire-holds')
            ->expectsOutput('Expired 1 booking hold(s).')
            ->assertSuccessful();
    }
}
