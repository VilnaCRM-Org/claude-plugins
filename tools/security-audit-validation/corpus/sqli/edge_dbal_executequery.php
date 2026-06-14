<?php
// SC-SQLI-E4: Doctrine DBAL executeQuery() alias sink with concatenated input.
function report(\Doctrine\DBAL\Connection $conn): array
{
    $status = $_GET['status'] ?? 'open';
    return $conn->executeQuery("SELECT * FROM reports WHERE status = '" . $status . "'")
        ->fetchAllAssociative();
}
