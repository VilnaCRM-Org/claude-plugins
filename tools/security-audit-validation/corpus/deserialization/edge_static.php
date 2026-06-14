<?php
// SC-DESER-E2: unserialize of a constant string, no taint.
function loadDefault(): mixed
{
    return unserialize('a:0:{}');
}
