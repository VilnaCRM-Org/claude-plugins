<?php

final class ProfileScript
{
    public function emit(): void
    {
        $user = $_GET['user'] ?? 'guest';
        // Sanitizer present, but WRONG context: value lands inside a JS string literal.
        $safeLooking = htmlspecialchars($user);
        echo "<script>var currentUser = '" . $safeLooking . "';</script>";
    }
}
