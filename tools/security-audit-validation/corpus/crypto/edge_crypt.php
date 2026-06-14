<?php
// SC-CRYPTO-E5: crypt() with an auto/weak scheme on a password.
function store(string $password): string
{
    return crypt($password);
}
