<?php
// SC-CRYPTO-E6: mhash with a weak algorithm over a credential.
function sign(string $password): string
{
    return mhash(MHASH_MD5, $password);
}
