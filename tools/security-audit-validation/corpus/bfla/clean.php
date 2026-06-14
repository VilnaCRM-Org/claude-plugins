<?php
// JC-BFLA-N: the destructive action requires the admin role.
final class AdminController
{
    public function deleteUser(UserRepository $repo, Security $security): void
    {
        if (!$security->isGranted('ROLE_ADMIN')) {
            throw new AccessDeniedException();
        }
        $repo->delete($_POST['userId']);
    }
}
