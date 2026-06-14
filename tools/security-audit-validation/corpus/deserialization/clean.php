<?php
// SC-DESER-N: json_decode instead of unserialize.
function loadState(): mixed
{
    return json_decode($_COOKIE['state'] ?? '', true);
}
