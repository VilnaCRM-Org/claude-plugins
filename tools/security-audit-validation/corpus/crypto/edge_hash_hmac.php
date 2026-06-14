<?php
// SC-CRYPTO-E4: HMAC-MD5 over a credential-named value is a weak primitive.
function sign(string $secret, string $body): string
{
    return hash_hmac('md5', $secret, $body);
}
