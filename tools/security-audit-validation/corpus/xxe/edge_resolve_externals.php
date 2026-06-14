<?php
// SC-XXE-E4: DOMDocument::$resolveExternals re-enables external entity loading.
function parse(string $xml): \DOMDocument
{
    $doc = new \DOMDocument();
    $doc->resolveExternals = true;
    $doc->loadXML($xml);
    return $doc;
}
