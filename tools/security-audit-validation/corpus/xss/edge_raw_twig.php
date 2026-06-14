<?php
// SC-XSS-E1: Twig template uses the |raw filter on user data (encoding disabled).
function tpl(): string
{
    return '<p>Hello {{ name|raw }}</p>';
}
