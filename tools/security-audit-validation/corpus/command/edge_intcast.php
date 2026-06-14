<?php
// SC-CMD-E5: an integer-coerced argument cannot inject (clean).
function pingN(): string
{
    $count = (int) ($_GET['count'] ?? 4);
    return (string) shell_exec("ping -c{$count} app.internal");
}
