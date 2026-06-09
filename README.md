# VilnaCRM Claude Plugins

Claude Code plugin marketplace for VilnaCRM engineering automation.

## Install

```bash
claude plugin marketplace add VilnaCRM-Org/claude-plugins
claude plugin install php-backend-sdlc@vilnacrm-plugins
```

## Plugins

| Plugin | Description |
| --- | --- |
| [php-backend-sdlc](plugins/php-backend-sdlc/) | Full-SDLC automation for PHP backend engineering: GitHub issue → BMAD planning → bmalph/Ralph implementation → multi-skill review + BMAD FR/NFR gate → QA → CI auto-fix → finished PR. |

## Repository layout

```
.claude-plugin/marketplace.json   # marketplace manifest
plugins/<name>/                   # one directory per plugin
docs/superpowers/specs/           # design documents
```

## Contributing

Plugins follow the [Claude Code plugin format](https://docs.claude.com/en/docs/claude-code/plugins):
`.claude-plugin/plugin.json` plus `commands/`, `agents/`, `skills/`, `hooks/`, `scripts/`.
Open an issue before submitting a new plugin or a major change.
