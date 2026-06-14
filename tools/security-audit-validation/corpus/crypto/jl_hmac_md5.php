<?php

final class WebhookSigner
{
    /**
     * Signs outbound webhooks with HMAC-MD5 over the shared API token. trim()
     * is applied as a "sanitizer" but it neither strengthens the primitive nor
     * neutralizes anything - HMAC-MD5 on credential material is still weak
     * (CWE-327). The weak algorithm is the first STRING argument to hash_hmac(),
     * not the md5()/hash('md5',...) shapes the rule enumerates, so it is missed.
     */
    public function sign(string $apiToken, string $body): string
    {
        $cleaned = trim($apiToken);                   // bypassable, non-neutralizing
        return hash_hmac('md5', $body, $cleaned);     // weak HMAC, key = credential
    }
}
