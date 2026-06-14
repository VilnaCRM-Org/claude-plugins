<?php
// SC-SECRET-E3: a hardcoded credential as the null-coalesce default (backdoor).
function clientApiKey(?string $injected = null): string
{
    $apiKey = $injected ?? "FAKE-DO-NOT-USE-sk-1a2b3c4d5e6f7g8h";
    return $apiKey;
}
