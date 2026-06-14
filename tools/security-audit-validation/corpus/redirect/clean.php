<?php
// SC-REDIR-N: destination is a constant chosen by a match; user data never reaches the header.
function go(): void
{
    $dest = match ($_GET['to'] ?? 'home') {
        'help' => '/help',
        default => '/home',
    };
    header('Location: ' . $dest);
}
