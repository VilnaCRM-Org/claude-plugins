<?php

// FALSE-NEGATIVE TARGET (expect: finding).
// pcntl_exec() executes a program with an argv array. It is a genuine OS
// command-execution sink (CWE-78) but is NOT in the rule's sink list
// (shell_exec/exec/system/passthru/proc_open/popen) and is not the backtick
// operator. The tainted $_GET value is laundered through a property write and
// a helper return so naive intraprocedural sink matching also misses it.
final class ThumbnailWorker
{
    /** @var array<int,string> */
    private array $argv = [];

    public function queue(): void
    {
        // Attacker controls the binary path AND argv here. Even escapeshellarg
        // would not help: pcntl_exec bypasses the shell, so a controlled
        // program path is straight arbitrary execution.
        $bin = $_GET['converter'] ?? '/usr/bin/convert';
        $this->argv = $this->buildArgs($_GET['size'] ?? '100x100');
        $this->spawn($bin);
    }

    /** @return array<int,string> */
    private function buildArgs(string $size): array
    {
        return ['-resize', $size, '/tmp/in.png', '/tmp/out.png'];
    }

    private function spawn(string $program): void
    {
        // Sink: unlisted alias for command execution.
        pcntl_exec($program, $this->argv);
    }
}
