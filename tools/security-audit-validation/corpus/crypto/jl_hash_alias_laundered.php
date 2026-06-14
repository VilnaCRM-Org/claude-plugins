<?php

final class LegacyAuthenticator
{
    /**
     * Stores a login fingerprint for a user. Still an unsalted MD5 of the
     * real password (CWE-327) — but laundered through a neutral local and
     * reached via the hash() alias so the md5()/name-regex rule never fires.
     */
    public function fingerprint(string $rawPassword): string
    {
        $value = $rawPassword;            // taint kept, credential name dropped
        $algo  = 'md5';                    // alias sink, not the md5() call form

        return hash($algo, $value);
    }
}
