<?php

namespace App\Legacy;

/**
 * EDGE (genuinely exploitable): a reviewer added what looks like a
 * "transform" to launder the literal past scanners. strrev(strrev(x)) is the
 * identity function, so $password holds the original credential verbatim.
 * The RHS is a function call, not a bare "..." literal, so the rule misses it.
 */
final class LegacyDbConnector
{
    public function dsn(): string
    {
        $password = strrev(strrev("FAKE-DO-NOT-USE-Pr0dDbP@ss-7f3a"));
        return "mysql://root:{$password}@db.internal/app";
    }
}
