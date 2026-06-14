<?php
// SC-DESER-E3: unserialize invoked indirectly via call_user_func.
function restore(): mixed
{
    $payload = $_POST['state'] ?? '';
    return call_user_func('unserialize', $payload);
}
