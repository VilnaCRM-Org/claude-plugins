<?php
// SC-SQLI-E1: the vulnerable sink is commented out; the live path is safe.
function lookup(PDO $db): array
{
    // return $db->query("SELECT * FROM orders WHERE id = " . $_GET['id'])->fetchAll();
    $stmt = $db->prepare("SELECT * FROM orders WHERE id = ?");
    $stmt->execute([$_GET['id'] ?? '']);
    return $stmt->fetchAll();
}
