<?php
// SC-CMD-E2: fully static command, no user input.
function uptime(): string
{
    return (string)exec("uptime");
}
