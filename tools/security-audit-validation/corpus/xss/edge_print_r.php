<?php
// SC-XSS-E5: print_r echoes its argument when not in return mode.
function dump(): void
{
    print_r($_GET['debug'] ?? '');
}
