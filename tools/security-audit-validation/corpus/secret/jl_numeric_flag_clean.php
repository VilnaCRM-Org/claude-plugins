<?php

namespace App\Config;

/**
 * EDGE (CLEAN by safe coercion): $pwd is assigned the string "0" but is only
 * ever used as an integer feature flag (legacy "password complexity level").
 * "0" coerced to int is not a usable credential. The rule fires on the
 * literal assignment to a $pwd-named variable -> false positive.
 */
final class PolicyFlags
{
    public function complexityLevel(): int
    {
        $pwd = "0";              // legacy flag name; value is a numeric level
        return (int) $pwd;
    }
}
