<?php
// SC-SQLI-N: prepared statement with a bound parameter.
function lookup(PDO $db): array
{
    $stmt = $db->prepare("SELECT * FROM orders WHERE id = ?");
    $stmt->execute([$_GET['id'] ?? '']);
    return $stmt->fetchAll();
}
