<?php
// JC-BOPLA-N: only an explicit allowlist of fields is writable.
final class ProfileController
{
    private const WRITABLE = ['displayName', 'bio'];

    public function update(User $user): void
    {
        foreach (self::WRITABLE as $field) {
            if (isset($_POST[$field])) {
                $user->{'set' . ucfirst($field)}($_POST[$field]);
            }
        }
    }
}
