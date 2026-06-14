<?php

declare(strict_types=1);

namespace App\Http\Service;

/**
 * Adversarial EDGE fixture: sanitizer PRESENT but BYPASSABLE => genuine finding.
 *
 * The developer believes they are safe because they only redirect when the
 * URL's host "starts with" the trusted domain. That check is broken:
 *   - "https://trusted.example.attacker.test/" passes str_starts_with on the
 *     full URL, and
 *   - parse_url-style prefix checks on host are defeated by
 *     "https://trusted.example@evil.test/" (userinfo) and by
 *     "//evil.test" protocol-relative URLs.
 * So user input still reaches the redirect. The sink is a framework-style
 * helper redirect() that ultimately calls header('Location: ...'), reached
 * through a method call and an array write rather than a direct header() in the
 * controller body.
 */
final class ProfileRedirector
{
    private const TRUSTED = 'https://trusted.example';

    /** @var array<string,string> */
    private array $headers = [];

    public function redirectBack(): void
    {
        // user input: ?return=//evil.test/steal  (protocol-relative bypass)
        $return = (string) ($_GET['return'] ?? '/');

        // Flawed allowlist: only a prefix check, trivially bypassable.
        $looksTrusted = str_starts_with($return, self::TRUSTED)
            || str_starts_with($return, '/');

        $location = $looksTrusted ? $return : '/';

        // "//evil.test/steal" starts with '/', so it is treated as trusted and
        // the browser follows it off-site as a protocol-relative redirect.
        $this->headers['Location'] = $location;
        $this->flush(302);
    }

    private function flush(int $code): void
    {
        http_response_code($code);
        foreach ($this->headers as $name => $value) {
            header("{$name}: {$value}");
        }
        exit;
    }
}
