<?php
// Secure: output is HTML-encoded with ENT_QUOTES via a project escaper wrapper.
// Only encoded data ever reaches echo, so this is not exploitable — but the
// wrapper hides htmlspecialchars from a rule that matches the call literally.
final class View
{
    private static function esc(string $v): string
    {
        return htmlspecialchars($v, ENT_QUOTES | ENT_HTML5, 'UTF-8');
    }

    public function show(): void
    {
        $name = $_GET['name'] ?? '';
        $safe = self::esc($name);
        echo $safe;
    }
}
