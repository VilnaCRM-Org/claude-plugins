<?php
// SC-SSRF-E3: the URL flows through a curl_setopt_array option set.
function probe(): string
{
    $ch = curl_init();
    curl_setopt_array($ch, [CURLOPT_URL => $_GET['u'] ?? '', CURLOPT_TIMEOUT => 5]);
    return (string) curl_exec($ch);
}
