<?php
// SC-SQLI-P: tainted $_GET concatenated into a query string.
function lookup(PDO $db): array
{
    $id = $_GET['id'] ?? '';
    return $db->query("SELECT * FROM orders WHERE id = " . $id)->fetchAll();
}
