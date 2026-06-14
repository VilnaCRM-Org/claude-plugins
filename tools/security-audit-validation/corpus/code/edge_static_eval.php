<?php
// SC-CODE-E2: eval of a constant literal, no taint.
function constEval(): mixed
{
    return eval("return 1 + 1;");
}
