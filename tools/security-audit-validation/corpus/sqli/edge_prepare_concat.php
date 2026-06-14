<?php
// SC-SQLI-E5: a prepared statement whose SQL is itself tainted prepares nothing.
function byActor(PDO $pdo): array
{
    $actor = $_GET['actor'] ?? 'system';
    $stmt = $pdo->prepare("SELECT * FROM audit_log WHERE actor = '" . $actor . "'");
    $stmt->execute();
    return $stmt->fetchAll();
}
