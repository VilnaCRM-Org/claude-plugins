<?php
// SC-XXE-N: parsing with LIBXML_NONET and entities left disabled.
function parse(string $xml): \DOMDocument
{
    $doc = new \DOMDocument();
    $doc->loadXML($xml, LIBXML_NONET);
    return $doc;
}
