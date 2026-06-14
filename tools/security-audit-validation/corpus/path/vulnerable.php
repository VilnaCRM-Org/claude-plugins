<?php
// SC-PATH-P: user filename concatenated into a path.
function read(): string
{
    $f = $_GET['f'] ?? '';
    return (string)file_get_contents("uploads/" . $f);
}
