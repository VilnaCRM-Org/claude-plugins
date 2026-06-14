<?php
// SC-DESER-E6: igbinary_unserialize has the same object-injection risk.
function rehydrate(): mixed
{
    return igbinary_unserialize($_POST['blob'] ?? '');
}
