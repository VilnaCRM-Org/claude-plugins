<?php
// SC-PATH-E1: local file inclusion from user input.
function loadPage(): void
{
    $page = $_GET['page'] ?? 'home';
    include($page . ".php");
}
