<?php
// SC-XSS-E4: exit() emits its string argument into the response.
function deny(): void
{
    exit('Access denied for ' . ($_GET['user'] ?? ''));
}
