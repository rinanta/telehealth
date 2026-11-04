<?php

namespace Tests\Feature;

use App\Services\FirebaseService;
use Mockery;
use Tests\TestCase;

class SessionExpiryCommandTest extends TestCase
{
    public function test_expiry_command_marks_each_overdue_confirmed_booking_as_no_show(): void
    {
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('getConfirmedBookingsPastNoShowDeadline')
            ->once()
            ->andReturn([
                ['id' => 'booking-overdue-1'],
                ['id' => 'booking-overdue-2'],
            ]);
        $firebase->shouldReceive('markBookingAsNoShow')
            ->once()
            ->with('booking-overdue-1')
            ->andReturn(true);
        $firebase->shouldReceive('markBookingAsNoShow')
            ->once()
            ->with('booking-overdue-2')
            ->andReturn(true);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->artisan('bookings:expire-sessions')
            ->expectsOutput('Marked 2 booking(s) as no-show.')
            ->assertSuccessful();
    }

    public function test_expiry_command_caps_at_max_bookings_per_run(): void
    {
        $overdue = array_map(
            static fn (int $i): array => ['id' => "booking-{$i}"],
            range(1, 15),
        );

        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('getConfirmedBookingsPastNoShowDeadline')
            ->once()
            ->andReturn($overdue);
        $firebase->shouldReceive('markBookingAsNoShow')
            ->times(10)
            ->andReturn(true);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->artisan('bookings:expire-sessions')
            ->expectsOutput('Marked 10 booking(s) as no-show.')
            ->assertSuccessful();
    }
}
