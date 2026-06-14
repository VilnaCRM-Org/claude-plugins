<?php
// SC-PATH-E3: file() and SplFileObject are file-read sinks too.
function readReport(): array
{
    $name = $_GET['name'] ?? '';
    return file("/srv/reports/" . $name . ".log");
}
