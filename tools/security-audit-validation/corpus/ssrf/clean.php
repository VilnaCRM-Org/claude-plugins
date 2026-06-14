<?php
// SC-SSRF-N: the URL is a constant chosen by a match; user data never reaches the sink.
function fetch(): string
{
    $url = match ($_GET['target'] ?? '') {
        'profile' => 'https://api.internal/profile',
        'status' => 'https://api.internal/status',
        default => null,
    };
    if ($url === null) {
        http_response_code(400);
        return '';
    }
    return (string)file_get_contents($url);
}
