<?php
// SC-CMD-E4: $_SERVER request headers are attacker-controlled too.
function logVisit(): void
{
    $client = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? 'unknown';
    shell_exec('echo ' . $client . ' >> /var/log/visits.log');
}
