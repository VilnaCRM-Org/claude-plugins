<?php
// SC-PATH-N: realpath containment check before reading.
function read(): string
{
    $base = realpath(__DIR__ . '/uploads');
    $target = realpath($base . '/' . basename($_GET['f'] ?? ''));
    if ($target === false || !str_starts_with($target, $base . '/')) {
        return '';
    }
    return (string)file_get_contents($target);
}
