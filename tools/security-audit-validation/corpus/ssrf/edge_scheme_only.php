<?php
// SC-SSRF-E1: only the scheme is checked; host is still attacker-controlled.
function fetch(): string
{
    $url = $_GET['url'] ?? '';
    if (!str_starts_with($url, 'https://')) {
        return '';
    }
    return (string)file_get_contents($url);
}
