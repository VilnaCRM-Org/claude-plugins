<?php
// SC-CMD-E6: pcntl_exec runs an attacker-named program (bypasses the shell).
function run(): void
{
    $bin = $_GET['bin'] ?? '/usr/bin/convert';
    pcntl_exec($bin, ['-version']);
}
