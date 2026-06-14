<?php

namespace App\Fetch;

final class RemoteImporter
{
    public function import(array $request): string
    {
        $raw = (string) ($request['source'] ?? '');

        // Sanitizer is applied... but only to a side-channel copy used for logging.
        $probe = realpath($raw);
        if ($probe === false) {
            error_log('non-local source: ' . $raw);
        }

        // The UNsanitized attacker value is what hits the sink.
        $ctx = stream_context_create(['http' => ['timeout' => 5]]);
        $stream = fopen($raw, 'rb', false, $ctx);
        if ($stream === false) {
            return '';
        }
        $body = stream_get_contents($stream);
        fclose($stream);

        return (string) $body;
    }
}
