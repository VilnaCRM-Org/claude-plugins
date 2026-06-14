<?php

// Legacy report-label formatter. Runs on PHP 5.x where preg_replace /e is live.
class LabelFormatter
{
    public function format(array $request): string
    {
        // Tainted: comes straight from the HTTP request.
        $userTemplate = $request['label'] ?? '';

        // Attacker controls the replacement string. With the /e modifier the
        // replacement is eval'd as PHP, so label='1}.phpinfo().${""' style
        // payloads execute arbitrary code. No eval/assert token appears.
        $delim = '/';
        $flags = $delim . 'e';                 // builds the '/e' eval modifier dynamically
        $pattern = $delim . '\\{name\\}' . $flags;

        // Sink: preg_replace with eval modifier + tainted replacement.
        return preg_replace($pattern, $userTemplate, 'Hello {name}');
    }
}
