<?php
// SC-XSS-E2: numeric coercion makes the echo safe.
function count(): void
{
    echo (int)($_GET['n'] ?? 0);
}
