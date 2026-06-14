<?php

declare(strict_types=1);

/**
 * Genuinely vulnerable XXE: LIBXML_NOENT (numeric value 2) is reconstructed
 * out of a raw integer so the constant identifier never appears at the sink.
 */
final class InvoiceXmlImporter
{
    // 2 is the documented value of LIBXML_NOENT; combined with DTDLOAD so a
    // SYSTEM entity declared in the inbound DTD is fetched and substituted.
    private const ENTITY_BIT = 2;        // == LIBXML_NOENT
    private const DTD_BIT    = 4;        // == LIBXML_DTDLOAD

    public function import(string $rawUserXml): \DOMDocument
    {
        $flags = self::ENTITY_BIT | self::DTD_BIT; // entities ON

        $doc = new \DOMDocument('1.0', 'UTF-8');
        // Sink the rule lists ($D->loadXML), but flags arrives as a variable
        // whose AST is an int/binary-or, not the LIBXML_NOENT identifier.
        $doc->loadXML($rawUserXml, $flags);

        return $doc;
    }
}
