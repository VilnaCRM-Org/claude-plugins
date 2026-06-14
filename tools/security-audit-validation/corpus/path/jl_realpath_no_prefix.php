<?php

final class ReportLoader
{
    public function load(): string
    {
        $name = $_REQUEST['report'] ?? 'q1';

        // realpath() resolves the ../ segments but does NOT pin the result
        // inside /opt/reports -- traversal still escapes the directory.
        $resolved = realpath('/opt/reports/' . $name . '.txt');
        if ($resolved === false) {
            return '';
        }

        // No prefix containment check follows; resolved may be /etc/passwd etc.
        $data = file_get_contents($resolved);
        return $data === false ? '' : $data;
    }
}
