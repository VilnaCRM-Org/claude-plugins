<?php
// SC-DESER-E5: yaml_parse with object support deserializes untrusted input.
function loadCfg(): mixed
{
    return yaml_parse($_POST['cfg'] ?? '');
}
