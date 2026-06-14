<?php
// JC-RATE-P: an unbounded user-controlled page size.
final class ListController
{
    public function list(OrderRepository $repo): array
    {
        $limit = (int)($_GET['limit'] ?? 20);
        return $repo->findBy([], null, $limit);
    }
}
