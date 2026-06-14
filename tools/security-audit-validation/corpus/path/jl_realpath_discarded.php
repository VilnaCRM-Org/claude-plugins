<?php

function stream_user_upload(string $dir, string $file): string
{
    // realpath is called, but only used as an existence guard. Its result is discarded.
    if (realpath($dir) === false) {
        throw new InvalidArgumentException('bad dir');
    }

    // The ORIGINAL tainted, non-canonicalized values are concatenated and used.
    $path = $dir . '/' . $file;

    // fopen is in the rule's sink list; sanitizer's output never reaches it => exploitable.
    $handle = fopen($path, 'rb');
    $buf = '';
    while (!feof($handle)) {
        $buf .= fread($handle, 8192);
    }
    fclose($handle);

    return $buf;
}
