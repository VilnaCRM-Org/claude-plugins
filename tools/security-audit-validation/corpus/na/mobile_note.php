<?php
// NC-NA-MOBILE: a backend endpoint that merely serves a mobile client.
// OWASP Mobile is N/A for a server-side backend (catalog: N/A-with-reason).
final class HealthController
{
    public function ping(): array
    {
        return ['status' => 'ok'];
    }
}
