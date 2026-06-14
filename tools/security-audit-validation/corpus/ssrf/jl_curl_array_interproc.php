<?php

namespace App\Outbound;

/**
 * Tainted host reaches libcurl through curl_setopt_array(), the bulk-options
 * sibling of curl_setopt(). The rule only matches the three-argument form
 * curl_setopt($CH, CURLOPT_URL, $U); the array form never trips it.
 */
final class MetadataProbe
{
    public function probe(): string
    {
        // $_SERVER source: attacker controls a forwarded header on many setups.
        $target = $_SERVER['HTTP_X_PROBE_HOST'] ?? 'metadata.internal';

        $ch = curl_init();
        $opts = [];
        $opts[CURLOPT_RETURNTRANSFER] = true;
        // Tainted value laundered into the options array under the CURLOPT_URL key.
        $opts[CURLOPT_URL] = 'http://' . $target . '/latest/meta-data/';
        $opts[CURLOPT_TIMEOUT] = 5;

        curl_setopt_array($ch, $opts);
        $body = curl_exec($ch);
        curl_close($ch);

        return (string) $body;
    }
}
