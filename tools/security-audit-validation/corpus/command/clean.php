<?php
// SC-CMD-N: argument escaped with escapeshellarg.
function ping(): string
{
    $host = escapeshellarg($_GET['host'] ?? '');
    return (string)shell_exec("ping -c1 " . $host);
}
