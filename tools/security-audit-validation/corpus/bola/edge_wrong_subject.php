<?php
// JC-BOLA-E1: authentication is checked, but not authorization of THIS object.
final class OrderController
{
    public function show(OrderRepository $repo, ?User $current): array
    {
        if ($current === null) {
            throw new AccessDeniedException();
        }
        // Authenticated, but any logged-in user can read any order.
        $order = $repo->find($_GET['id']);
        return $order->toArray();
    }
}
