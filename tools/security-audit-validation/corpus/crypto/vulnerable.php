<?php
// SC-CRYPTO-P: md5 used to hash a password.
function store(string $password): string
{
    return md5($password);
}
