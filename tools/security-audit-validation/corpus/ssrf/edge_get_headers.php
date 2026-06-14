<?php
// SC-SSRF-E4: get_headers fetches an attacker-chosen URL.
function probe(): array
{
    return (array) get_headers($_GET['u'] ?? '');
}
