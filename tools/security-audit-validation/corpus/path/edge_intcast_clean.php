<?php
// SC-PATH-E5: an integer-coerced path segment cannot traverse (clean).
function page(): string
{
    $n = (int) ($_GET['n'] ?? 1);
    return (string) file_get_contents("/srv/pages/" . $n . ".html");
}
