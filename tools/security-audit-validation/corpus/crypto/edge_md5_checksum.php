<?php
// SC-CRYPTO-E2: md5 of file bytes for a non-security cache key is acceptable.
function cacheKey(string $path): string
{
    $data = (string)file_get_contents($path);
    return md5($data);
}
