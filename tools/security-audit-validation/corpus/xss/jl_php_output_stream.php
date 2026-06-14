<?php
// Reflected XSS by writing to php://output — identical to echo at the SAPI
// level, but fopen()/fwrite() are not enumerated as output sinks by the rule.
function stream_banner(): void
{
    $msg = $_GET['msg'] ?? '';
    $out = fopen('php://output', 'wb');
    fwrite($out, "<div class=\"flash\">{$msg}</div>");
    fclose($out);
}
