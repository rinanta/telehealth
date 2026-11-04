<?php

namespace App\Exceptions;

use RuntimeException;
use Throwable;

class MidtransApiException extends RuntimeException
{
    public function __construct(
        string $message,
        public readonly string $failureType,
        public readonly ?int $providerStatus = null,
        ?Throwable $previous = null,
    ) {
        parent::__construct($message, previous: $previous);
    }
}
