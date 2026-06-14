<?php
// JC-BOPLA-P: hydrates an entity from the whole request body, incl. privileged fields.
final class ProfileController
{
    public function update(User $user): void
    {
        foreach ($_POST as $field => $value) {
            $user->{'set' . ucfirst($field)}($value);
        }
        // An attacker can set isAdmin=1 via the request body.
    }
}
