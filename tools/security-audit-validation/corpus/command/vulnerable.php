<?php
// SC-CMD-P: tainted host concatenated into a shell command.
function ping(): string
{
    $host = $_GET['host'] ?? '';
    return (string)shell_exec("ping -c1 " . $host);
}
