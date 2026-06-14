<?php
// JC-AUTH-N: constant-time comparison behind a rate-limit guard.
final class TokenAuth
{
    public function __construct(private RateLimiter $limiter)
    {
    }

    public function check(string $expected): bool
    {
        if (!$this->limiter->consume()->isAccepted()) {
            throw new TooManyRequestsException();
        }
        return hash_equals($expected, $_GET['token'] ?? '');
    }
}
