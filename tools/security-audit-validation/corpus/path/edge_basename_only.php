<?php
// SC-PATH-E2: basename alone does not contain traversal (symlink/abs handling).
function read(): string
{
    $f = basename($_GET['f'] ?? '');
    return (string)file_get_contents("uploads/" . $f);
}
