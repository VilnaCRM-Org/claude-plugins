<?php
// SC-SQLI-E3: integer cast neutralizes the value before concatenation.
function lookup(PDO $db): array
{
    $id = (int)($_GET['id'] ?? 0);
    return $db->query("SELECT * FROM orders WHERE id = " . $id)->fetchAll();
}
