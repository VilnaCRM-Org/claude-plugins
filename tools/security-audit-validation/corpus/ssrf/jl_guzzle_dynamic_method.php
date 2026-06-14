<?php

namespace App\Http;

use GuzzleHttp\ClientInterface;

final class WebhookRelay
{
    public function __construct(private ClientInterface $client) {}

    public function relay(array $input): string
    {
        // Attacker controls host via request body.
        $parts = [];
        $parts['scheme'] = ($input['secure'] ?? false) ? 'https' : 'http';
        $parts['host'] = $input['endpoint'] ?? 'localhost';

        $scheme = $parts['scheme'];
        $host = $parts['host'];
        // Tainted host flows into the request URI via interpolation.
        $uri = "${scheme}://${host}/v1/proxy";

        // Sink is reached through a variable method name, not a literal ->request.
        $verb = 'request';
        $response = $this->client->{$verb}('GET', $uri, ['timeout' => 5]);

        return (string) $response->getBody();
    }
}
