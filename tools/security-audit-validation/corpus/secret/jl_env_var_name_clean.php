<?php

namespace App\Config;

/**
 * SECURE: the string literal assigned to $secret is the NAME of an
 * environment variable (a config key), immediately passed to getenv() to
 * resolve the real value at runtime. No credential is embedded. The rule
 * fires on "$secret = <literal>" and produces a false positive.
 */
final class SecretResolver
{
    public function resolve(): string
    {
        $secret = "APP_OAUTH_CLIENT_SECRET";   // an env-var key, not a value
        return (string) getenv($secret);
    }
}
