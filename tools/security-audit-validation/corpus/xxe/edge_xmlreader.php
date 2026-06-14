<?php
// SC-XXE-E3: XMLReader enables entity substitution via setParserProperty.
function parse(string $xml): \XMLReader
{
    $r = new \XMLReader();
    $r->xml($xml);
    $r->setParserProperty(\XMLReader::SUBST_ENTITIES, true);
    return $r;
}
