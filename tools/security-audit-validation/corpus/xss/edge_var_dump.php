<?php
// SC-XSS-E6: var_dump writes user input to the response.
function dump(): void
{
    var_dump($_GET['debug'] ?? '');
}
