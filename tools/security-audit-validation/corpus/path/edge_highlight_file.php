<?php
// SC-PATH-E4: highlight_file is a file-read sink.
function show(): void
{
    highlight_file("/srv/snippets/" . ($_GET['f'] ?? ''));
}
