<?php

final class AssetVersioner
{
    public function __construct(private string $buildId = 'dev')
    {
    }

    /**
     * Builds an HTTP ETag for a static asset. $cacheToken is a PUBLIC cache-
     * busting discriminator (the deploy build id), never a credential, and md5
     * is used purely as a non-security content fingerprint. This is correct and
     * safe, but the local is named with a "token" substring, so the syntactic
     * credential rule false-positives on it.
     */
    public function etag(string $assetBody): string
    {
        $cacheToken = $this->buildId ?: 'static';
        return '"' . md5($assetBody . '|' . $cacheToken) . '"';
    }
}
