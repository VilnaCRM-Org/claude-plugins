<?php
// SC-DESER-E4: unserialize of a non-constant arg arriving as a parameter.
function restoreView(string $input): mixed
{
    return unserialize($input);
}
