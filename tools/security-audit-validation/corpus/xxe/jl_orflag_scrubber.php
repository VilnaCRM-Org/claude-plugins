<?php

declare(strict_types=1);

namespace App\Upload;

/**
 * Edge case: a "sanitizer" pretends to strip the DTD before parsing with
 * entities ON, but the blacklist is trivially bypassable (case / whitespace),
 * so a crafted DOCTYPE survives and the SYSTEM entity is expanded.
 * The flags use the realistic LIBXML_NOENT | LIBXML_DTDLOAD or-expression,
 * which the rule's argument-position ellipsis does not match. Exploitable.
 */
final class DocImporter
{
    private function scrub(string $xml): string
    {
        // Naive blacklist -- misses '<!dOcTyPe', "<!\nDOCTYPE", nested refs, etc.
        return str_replace(['<!DOCTYPE', '<!ENTITY'], '', $xml);
    }

    public function import(string $userXml): \DOMDocument
    {
        $clean = $this->scrub($userXml);

        $doc = new \DOMDocument('1.0', 'UTF-8');
        // Compound flag arg: LIBXML_NOENT is nested in a binary-or, not a
        // standalone argument node -> the pattern's ellipsis never matches it.
        $doc->loadXML($clean, LIBXML_NOENT | LIBXML_DTDLOAD);

        return $doc;
    }
}
