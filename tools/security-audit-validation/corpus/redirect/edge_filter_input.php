<?php
// SC-REDIR-E5: filter_input(INPUT_GET, ...) is a user-input source.
function go(): void
{
    $next = filter_input(INPUT_GET, 'next');
    header('Location: ' . $next);
}
