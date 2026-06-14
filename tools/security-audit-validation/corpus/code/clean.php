<?php
// SC-CODE-N: whitelisted operations via match, no eval.
function compute(): int
{
    $op = $_POST['op'] ?? 'add';
    return match ($op) {
        'add' => 1 + 1,
        'sub' => 1 - 1,
        default => 0,
    };
}
