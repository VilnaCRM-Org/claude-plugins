<?php

use Twig\Environment;

final class EmailBodyRenderer
{
    public function __construct(private Environment $engine) {}

    private function sanitize(string $s): string
    {
        // Bypassable: only strips {{ }} output tags, not {% %} statement tags.
        return str_replace(['{{', '}}'], '', $s);
    }

    public function render(array $payload): string
    {
        // Tainted: user-controlled email subject template.
        $raw = (string) ($payload['subject_tpl'] ?? '');
        $clean = $this->sanitize($raw);

        // Bypass example: subject_tpl uses {% set x = ... %} or filter chains
        // that survive the str_replace -> Twig sandbox-less SSTI => RCE.
        // Receiver is $this->engine, NOT a var named $twig.
        $template = $this->engine->createTemplate($clean);

        return $template->render(['user' => 'placeholder-user']);
    }
}
