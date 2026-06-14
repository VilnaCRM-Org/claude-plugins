<?php

final class LegacyCredentialStore
{
    private string $hashColumn = '';

    /**
     * Persists the account password using crypt() with the "$1$" prefix, which
     * selects the MD5-based crypt scheme - a deprecated, GPU-cheap password hash
     * (CWE-327). The plaintext is laundered into a neutral local and a property
     * write, and the sink is crypt() (not md5/sha1/hash), so the name-regex rule
     * never fires. Genuinely exploitable: offline cracking of the stored hash.
     */
    public function persist(string $accountPassword): void
    {
        $material = $accountPassword;                 // credential name dropped here
        $scheme   = '$1$' . substr(sha1('pepper'), 0, 8) . '$';
        $this->hashColumn = crypt($material, $scheme); // MD5-crypt sink
    }
}
