<?php
// SC-XXE-E1: simplexml_load_string with LIBXML_NOENT.
function parse(string $xml): \SimpleXMLElement
{
    return simplexml_load_string($xml, 'SimpleXMLElement', LIBXML_NOENT);
}
