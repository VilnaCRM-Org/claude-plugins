<?php
// SC-XSS-E3: printf writes user input straight to output.
function greet(): void
{
    printf('<p>%s</p>', $_GET['name'] ?? '');
}
