<?php

final class ReportArchiveReader
{
    private string $baseDir = '/srv/app/reports';

    /** @var array<string,string> */
    private array $ctx = [];

    public function load(string $requestedName): string
    {
        // Taint enters via request param, hops through a property bag.
        $this->ctx['name'] = $requestedName;
        $folder = $this->baseDir;
        // String interpolation builds the path; no realpath, no containment check.
        $target = "${folder}/${this->ctx['name']}.log";

        // SplFileObject is a genuine file-read sink, but it is NOT in the rule's list.
        $fh = new SplFileObject($target, 'r');
        $first = $fh->fgets();

        // file() is also a real read sink the rule does not enumerate.
        $lines = file($target, FILE_IGNORE_NEW_LINES);

        return $first . "\n" . implode("\n", $lines ?: []);
    }
}
