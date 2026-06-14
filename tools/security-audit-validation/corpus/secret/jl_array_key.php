<?php

namespace App\Infrastructure\Search;

/**
 * The credential lives in an ARRAY VALUE keyed by 'api_key'. The holder
 * variable is innocuously named ($settings / $token), and the literal is
 * routed through a benign-named intermediate before landing in the map.
 */
final class ElasticConnectionFactory
{
    public function build(): array
    {
        $token = "es_FAKE_AbCdEf0123456789hardcoded";
        $settings = [
            'host'    => getenv('ES_HOST'),
            'api_key' => $token,
        ];

        return $settings;
    }
}
