<?php
// NC-NA-MEMSAFE: managed PHP has no manual memory management; memory-safety
// CWEs (buffer overflow, OOB, use-after-free) are N/A-with-reason.
function sizeOf(array $buffer): int
{
    return count($buffer);
}
