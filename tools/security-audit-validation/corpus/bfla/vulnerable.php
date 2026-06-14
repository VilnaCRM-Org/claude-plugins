<?php
// JC-BFLA-P: an admin-only action with no role guard.
final class AdminController
{
    public function deleteUser(UserRepository $repo): void
    {
        $repo->delete($_POST['userId']);
    }
}
