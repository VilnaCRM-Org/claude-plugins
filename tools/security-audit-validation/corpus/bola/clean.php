<?php
// JC-BOLA-N: ownership asserted against the authenticated user.
final class OrderController
{
    public function show(OrderRepository $repo, User $current): array
    {
        $order = $repo->find($_GET['id']);
        if ($order === null || $order->getOwnerId() !== $current->getId()) {
            throw new AccessDeniedException();
        }
        return $order->toArray();
    }
}
