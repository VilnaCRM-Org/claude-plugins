<?php
// SC-PATH-E6: copy() with an attacker-controlled source path.
function grab(): bool
{
    return copy($_GET['src'] ?? '', '/tmp/cached');
}
