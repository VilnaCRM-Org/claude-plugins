<?php

final class GreetingView
{
    private function pull(string $key): string
    {
        // tainted: attacker-controlled query parameter
        return (string) ($_GET[$key] ?? '');
    }

    public function render(): void
    {
        $name = $this->pull('name');
        $line = 'Welcome back, ' . $name;

        // printf is an output sink just like echo, but the rule does not list it.
        // $line is the %s argument -> reflected unescaped into the HTML response.
        printf('<p class="greeting">%s</p>', $line);
    }
}
