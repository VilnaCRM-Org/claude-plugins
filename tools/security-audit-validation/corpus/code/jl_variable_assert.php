<?php

// Lightweight precondition checker for a legacy rules engine (PHP 7.0).
final class PreconditionGuard
{
    /** @var callable-string */
    private string $evaluator;

    public function __construct()
    {
        // Split so the literal 'assert' never appears contiguously.
        $this->evaluator = 'ass' . 'ert';
    }

    public function check(array $input): void
    {
        // Tainted condition string from an admin-supplied rule definition.
        $rule = $input['precondition'] ?? 'true';

        $fn = $this->evaluator;

        // Indirect call: $fn === 'assert'. On PHP <8 a string condition is
        // compiled and executed -> arbitrary code execution.
        // e.g. precondition = "phpinfo() || true"
        $fn($rule);
    }
}
