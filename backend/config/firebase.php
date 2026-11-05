<?php

return [
    'project_id' => env('FIREBASE_PROJECT_ID'),
    'credentials' => env(
        'FIREBASE_CREDENTIALS',
        storage_path('app/private/firebase-service-account.json'),
    ),
    // Small allowance for clock skew between Firebase and the local Laravel host.
    'token_clock_skew_seconds' => (int) env('FIREBASE_TOKEN_CLOCK_SKEW_SECONDS', 30),
];
