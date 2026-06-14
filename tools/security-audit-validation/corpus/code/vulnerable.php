<?php
// SC-CODE-P: eval of user-controlled expression.
function compute(): mixed
{
    $expr = $_POST['expr'] ?? '0';
    return eval("return " . $expr . ";");
}
