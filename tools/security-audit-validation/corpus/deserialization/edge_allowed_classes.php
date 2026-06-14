<?php
// SC-DESER-E1: allowed_classes=false reduces gadgets but input is still attacker-controlled.
function loadState(): mixed
{
    return unserialize($_COOKIE['state'] ?? '', ['allowed_classes' => false]);
}
