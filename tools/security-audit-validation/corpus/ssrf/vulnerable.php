<?php
// SC-SSRF-P: user URL fetched directly.
function fetch(): string
{
    $url = $_GET['url'] ?? '';
    return (string)file_get_contents($url);
}
