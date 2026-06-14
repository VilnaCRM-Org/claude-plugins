<?php
// SC-SQLI-E6: PDO::quote() driver-escapes the value (clean).
function byLabel(PDO $db): array
{
    $label = $db->quote($_GET['label'] ?? '');
    return $db->query("SELECT id FROM tags WHERE label = " . $label)->fetchAll();
}
