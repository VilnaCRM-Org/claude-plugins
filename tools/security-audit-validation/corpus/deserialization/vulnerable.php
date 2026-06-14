<?php
// SC-DESER-P: unserialize of a user-controlled cookie.
function loadState(): mixed
{
    return unserialize($_COOKIE['state'] ?? '');
}
