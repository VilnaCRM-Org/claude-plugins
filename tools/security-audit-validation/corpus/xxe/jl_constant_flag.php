<?php

declare(strict_types=1);

namespace App\Feed;

/**
 * Vulnerable XXE. The LIBXML_NOENT bit is resolved at runtime via constant()
 * from a string, so the bare identifier token never appears as an argument
 * node at the sink -- yet libxml still receives the NOENT flag and substitutes
 * external SYSTEM entities in attacker-supplied XML.
 */
final class PriceFeedLoader
{
    public function load(string $userXml): \SimpleXMLElement|false
    {
        // Flag name arrives as plain data; constant() turns it into int 2.
        $flagName = 'LIBXML_NOENT';
        $opts = LIBXML_DTDLOAD | constant($flagName); // entities ON at parse

        return simplexml_load_string($userXml, \SimpleXMLElement::class, $opts);
    }
}
