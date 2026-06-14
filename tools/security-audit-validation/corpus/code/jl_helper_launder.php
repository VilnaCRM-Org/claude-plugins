<?php

final class ExpressionEngine
{
    /** Evaluates a user-supplied arithmetic expression. */
    public function evaluate(): mixed
    {
        $raw = $_GET['expr'] ?? '0';        // tainted source
        return $this->compile($raw);         // hop across a method boundary
    }

    private function compile(string $code): mixed
    {
        // No checks. eval() runs attacker PHP. Reached only via the helper,
        // so a source-in-same-function taint match never connects the chain.
        return eval('return ' . $code . ';');
    }
}
