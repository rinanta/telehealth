<?php

namespace App\Console\Commands;

use App\Services\FirebaseService;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

#[Signature('bookings:expire-holds')]
#[Description('Expire unpaid bookings and release their slot holds.')]
class ExpireBookingHolds extends Command
{
    private const MAX_BOOKINGS_PER_RUN = 10;

    public function handle(FirebaseService $firebase): int
    {
        $expiredCount = 0;

        foreach (array_slice($firebase->getExpiredBookingHolds(), 0, self::MAX_BOOKINGS_PER_RUN) as $booking) {
            $bookingId = $booking['id'] ?? null;

            if (is_string($bookingId) && $firebase->expireBookingHold($bookingId)) {
                $expiredCount++;
            }
        }

        $this->info("Expired {$expiredCount} booking hold(s).");

        return self::SUCCESS;
    }
}
