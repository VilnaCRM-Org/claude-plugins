<?php
// SC-SQLI-E7: the multipart upload filename ($_FILES[..]['name']) is attacker-controlled.
function journal(PDO $db): void
{
    $name = $_FILES['doc']['name'] ?? 'untitled';
    $db->query("INSERT INTO uploads (label) VALUES ('" . $name . "')");
}
