<?php
// Reflected XSS through Twig with autoescape disabled via {% autoescape false %}
// instead of the |raw filter, so the '|raw' regex never matches and {{ c }}
// renders the attacker's comment with no HTML encoding.
function render_comment(\Twig\Environment $twig): string
{
    $comment = $_POST['comment'] ?? '';
    $tpl = '{% autoescape false %}<p>{{ c }}</p>{% endautoescape %}';
    return $twig->createTemplate($tpl)->render(['c' => $comment]);
}
