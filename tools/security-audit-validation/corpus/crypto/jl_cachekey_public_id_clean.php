<?php

final class ResponseCache
{
    /**
     * Build a per-tenant cache bucket key. The argument is the PUBLIC api key
     * identifier (not the secret key material), and md5 is used only as a fast
     * non-cryptographic bucketing digest — no credential is protected here.
     */
    public function bucketFor(string $public_api_key_id): string
    {
        return 'resp_' . md5($public_api_key_id);
    }
}
