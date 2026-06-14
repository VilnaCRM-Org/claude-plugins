<?php
// SC-XSS-N: output encoded with htmlspecialchars.
function greet(): void
{
    echo htmlspecialchars($_GET['name'] ?? '', ENT_QUOTES);
}
