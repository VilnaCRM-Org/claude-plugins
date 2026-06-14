<?php
// SC-REDIR-E4: a commented-out sink + an integer-only dynamic part (clean).
final class PaginationRedirect
{
    public function handle(): void
    {
        // header("Location: {$_GET['next']}");  // documented past bug; not live
        $page = (int) ($_GET['page'] ?? 1);
        header('Location: /listing?page=' . $page, true, 302);
    }
}
