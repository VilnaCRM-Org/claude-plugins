<?php
// SC-CMD-E1: escapeshellcmd does NOT neutralize argument injection.
function ping(): string
{
    $host = escapeshellcmd($_GET['host'] ?? '');
    return (string)shell_exec("ping -c1 " . $host);
}
