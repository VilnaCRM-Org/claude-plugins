<?php
// SC-CMD-E3: the backtick operator executes a shell command with user input.
function trace(): string
{
    $host = $_GET['host'] ?? 'localhost';
    return (string) `traceroute -c1 $host`;
}
