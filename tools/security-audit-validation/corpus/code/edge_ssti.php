<?php
// SC-CODE-E1: SSTI via Twig createTemplate on user input.
function render(\Twig\Environment $twig): string
{
    $tpl = $_GET['tpl'] ?? '';
    return $twig->createTemplate($tpl)->render([]);
}
