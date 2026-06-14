<?php
// Safe coercion routed through a typed helper: the helper's int return type
// guarantees no string ever reaches the concatenated query.
class CatalogGateway
{
    private function asId(mixed $v): int
    {
        return (int) $v;
    }

    public function load(PDO $db): array
    {
        $id = $this->asId($_REQUEST['pid'] ?? 0);
        return $db->query("SELECT * FROM products WHERE id = " . $id)->fetchAll();
    }
}
