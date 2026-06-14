<?php
// JC-RATE-N: the page size is clamped to a hard maximum.
final class ListController
{
    private const MAX = 100;

    public function list(OrderRepository $repo): array
    {
        $limit = min(self::MAX, max(1, (int)($_GET['limit'] ?? 20)));
        return $repo->findBy([], null, $limit);
    }
}
