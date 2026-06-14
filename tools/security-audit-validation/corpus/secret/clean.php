<?php
// SC-SECRET-N: the credential is read from the environment.
final class Client
{
    public function key(): string
    {
        return (string)getenv('API_KEY');
    }
}
