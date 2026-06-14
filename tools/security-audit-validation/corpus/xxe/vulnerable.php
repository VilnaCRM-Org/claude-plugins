<?php
// SC-XXE-P: LIBXML_NOENT enables external entity expansion.
function parse(string $xml): \DOMDocument
{
    $doc = new \DOMDocument();
    $doc->loadXML($xml, LIBXML_NOENT);
    return $doc;
}
