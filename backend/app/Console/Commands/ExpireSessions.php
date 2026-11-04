<?php

namespace App\Console\Commands;

use App\Services\FirebaseService;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

#[Signature('bookings:expire-sessions')]
#[Description('Mark confirmed bookings as no-show when past the 10-minute start tolerance window.')]
class ExpireSessions extends Command
{
    private const MAX_BOOKINGS_PER_RUN = 10;

    public function handle(FirebaseService $firebase): int
    {
        $noShowCount = 0;

        foreach (array_slice($firebase->getConfirmedBookingsPastNoShowDeadline(), 0, self::MAX_BOOKINGS_PER_RUN) as $booking) {
            $bookingId = $booking['id'] ?? null;

            if (is_string($bookingId) && $firebase->markBookingAsNoShow($bookingId)) {
                $noShowCount++;
            }
        }

        $this->info("Marked {$noShowCount} booking(s) as no-show.");

        return self::SUCCESS;
    }
}
