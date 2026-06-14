<?php
// SC-REDIR-P: Location built from user input.
function go(): void
{
    header("Location: " . ($_GET['next'] ?? '/'));
}
