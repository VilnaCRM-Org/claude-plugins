<?php

declare(strict_types=1);

namespace App\Http\Controller;

/**
 * SECURE -- intended FALSE POSITIVE (safe coercion the rule cannot follow).
 *
 * User input is coerced through a backed enum (Target::tryFrom). tryFrom returns
 * a known enum case or null; an unknown/attacker value yields null and falls
 * back to the default case. The destination ultimately comes from the enum's own
 * ->path() constant table, so no attacker-controlled string can reach the
 * Location header. The raw $_GET value is interpolated only into a non-sink log.
 */
enum Target: string
{
    case Home = 'home';
    case Help = 'help';

    public function path(): string
    {
        return match ($this) {
            self::Home => '/home',
            self::Help => '/help',
        };
    }
}

final class EnumRedirector
{
    public function go(): void
    {
        $raw = (string) ($_GET['to'] ?? 'home');
        $target = Target::tryFrom($raw) ?? Target::Home;

        error_log("redirect requested: {$raw}");

        header('Location: ' . $target->path(), true, 302);
        exit;
    }
}
