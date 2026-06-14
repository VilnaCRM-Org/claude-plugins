<?php
// SC-SSRF-E2: a hardcoded internal URL, no user input.
function fetch(): string
{
    return (string)file_get_contents('https://api.internal/health');
}
