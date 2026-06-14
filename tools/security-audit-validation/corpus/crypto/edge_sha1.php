<?php
// SC-CRYPTO-E1: sha1 is also unsuitable for passwords.
function store(string $password): string
{
    return sha1($password);
}
