<?php
// SC-REDIR-E1: leading-slash check is bypassable via "//evil.com".
function go(): void
{
    $next = $_GET['next'] ?? '/';
    if ($next === '' || $next[0] !== '/') {
        $next = '/';
    }
    header('Location: ' . $next);
}
