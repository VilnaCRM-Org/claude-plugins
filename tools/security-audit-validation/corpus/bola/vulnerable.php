<?php
// JC-BOLA-P: loads an object by id with no ownership check.
final class OrderController
{
    public function show(OrderRepository $repo): array
    {
        $order = $repo->find($_GET['id']);
        return $order->toArray();
    }
}
