<?php
// SC-SQLI-E2: taint laundered through an intermediate variable.
function lookup(PDO $db): array
{
    $raw = $_GET['id'] ?? '';
    $q = "SELECT * FROM orders WHERE id = " . $raw;
    return $db->query($q)->fetchAll();
}
