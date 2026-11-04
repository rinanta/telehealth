<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Schedule::useCache('file');

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Schedule::command('bookings:expire-holds')
    ->everyMinute()
    ->withoutOverlapping(15);

Schedule::command('bookings:expire-sessions')
    ->everyMinute()
    ->withoutOverlapping(15);
