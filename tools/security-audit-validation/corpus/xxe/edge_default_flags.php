<?php
// SC-XXE-E2: default flags; libxml >= 2.9 disables external entities by default.
function parse(string $xml): \DOMDocument
{
    $doc = new \DOMDocument();
    $doc->loadXML($xml);
    return $doc;
}
