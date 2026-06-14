<?php
// SC-REDIR-E3: a multi-arg header() call still reaches the Location sink.
function go(): void
{
    header('Location: ' . ($_GET['next'] ?? '/'), true, 302);
}
