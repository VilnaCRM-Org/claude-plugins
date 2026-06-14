<?php
// JC-AUTH-P: non-constant-time token comparison, no attempt throttling.
final class TokenAuth
{
    public function check(string $expected): bool
    {
        $given = $_GET['token'] ?? '';
        return $given == $expected;
    }
}
