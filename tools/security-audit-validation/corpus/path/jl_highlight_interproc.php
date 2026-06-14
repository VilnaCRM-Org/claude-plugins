<?php

final class SnippetViewer
{
    private string $target = '';

    public function render(): void
    {
        // $_SERVER source: e.g. GET /viewer.php/../../../etc/passwd -> PATH_INFO
        $ctx = [];
        $ctx['rel'] = $_SERVER['PATH_INFO'] ?? '/default.php';

        // basename() is intentionally NOT a sufficient sanitizer per the rule,
        // and here it is bypassable because the dir part is kept via interpolation.
        $base = '/srv/snippets';
        $rel  = ltrim($ctx['rel'], '/');
        $this->target = "${base}/${rel}";

        $this->emit();
    }

    private function emit(): void
    {
        // highlight_file() dumps the full source of ANY path it is given.
        // It is a real LFI sink but is absent from the rule's sink list.
        highlight_file($this->target);
    }
}
