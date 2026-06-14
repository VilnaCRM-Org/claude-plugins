<?php
// SC-CRYPTO-E3: hash('md5', ...) is the alias form of the weak primitive.
function store(string $password): string
{
    return hash('md5', $password);
}
