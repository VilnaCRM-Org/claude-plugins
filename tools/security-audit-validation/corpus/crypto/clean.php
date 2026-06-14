<?php
// SC-CRYPTO-N: password_hash with a strong default algorithm.
function store(string $password): string
{
    return password_hash($password, PASSWORD_DEFAULT);
}
