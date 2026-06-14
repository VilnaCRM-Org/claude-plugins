<?php
// SC-XSS-P: user input echoed without encoding.
function greet(): void
{
    echo $_GET['name'] ?? '';
}
