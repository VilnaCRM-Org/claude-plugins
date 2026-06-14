"""Fixture manifest for the security-audit validation campaign.

Single source of truth shared by the detection harness (``detect.py``), the LLM
judge lane (``judge/run_seed_judge.py``), and the test suite. Each entry maps a
test-case id from
``plugins/php-backend-sdlc/docs/testing/security-audit-test-cases.md`` to a
fixture file under ``corpus/`` and its expected verdicts.

This module is **pure data**: lists of frozen dataclasses plus tiny accessors.
The detection/compare logic lives in ``detect.py`` so the gate is testable
without semgrep installed.
"""

from __future__ import annotations

import dataclasses

# Static-lane verdicts. ``None`` means the static lane does not assert this
# fixture (a logic family with no sound static signature — judge lane only).
FINDING = "finding"
CLEAN = "clean"

# Judge-lane verdicts.
J_FINDING = "FINDING"
J_CLEAN = "CLEAN"
J_NA = "NA"


@dataclasses.dataclass(frozen=True)
class Fixture:
    """One corpus fixture and its expected detection verdicts."""

    cid: str  # stable test-case id (e.g. "SC-SQLI-P")
    family: str  # dispatch family tag, matches rules' metadata.family
    path: str  # path relative to corpus/ (POSIX)
    cwe: str  # primary CWE id
    static_expect: str | None  # FINDING | CLEAN | None (judge-only)
    judge_expect: str  # J_FINDING | J_CLEAN | J_NA


@dataclasses.dataclass(frozen=True)
class DepCase:
    """A composer.json dependency fixture (FR-7 in-tree dep demonstration)."""

    cid: str
    path: str
    package: str
    expect_vulnerable: bool


# Known-vulnerable version windows per package, as [low_inclusive, high_exclusive)
# tuples of (major, minor, patch). Sourced from published advisories; encoded
# in-tree so the dep lane is deterministic and offline (stands in for an online
# `composer audit`). guzzlehttp/guzzle: CVE-2022-31090/31091 fixed in 6.5.6 and
# 7.4.3 respectively.
VULN_RANGES: dict[str, list[tuple[tuple[int, int, int], tuple[int, int, int]]]] = {
    "guzzlehttp/guzzle": [
        ((0, 0, 0), (6, 5, 6)),
        ((7, 0, 0), (7, 4, 3)),
    ],
}


# --- Static-detectable families -------------------------------------------
_STATIC_FIXTURES: tuple[Fixture, ...] = (
    # SQLi (CWE-89)
    Fixture("SC-SQLI-P", "sqli", "sqli/vulnerable.php", "CWE-89", FINDING, J_FINDING),
    Fixture("SC-SQLI-N", "sqli", "sqli/clean.php", "CWE-89", CLEAN, J_CLEAN),
    Fixture("SC-SQLI-E1", "sqli", "sqli/edge_commented.php", "CWE-89", CLEAN, J_CLEAN),
    Fixture(
        "SC-SQLI-E2", "sqli", "sqli/edge_laundered.php", "CWE-89", FINDING, J_FINDING
    ),
    Fixture("SC-SQLI-E3", "sqli", "sqli/edge_intcast.php", "CWE-89", CLEAN, J_CLEAN),
    # Command injection (CWE-78)
    Fixture(
        "SC-CMD-P", "command", "command/vulnerable.php", "CWE-78", FINDING, J_FINDING
    ),
    Fixture("SC-CMD-N", "command", "command/clean.php", "CWE-78", CLEAN, J_CLEAN),
    Fixture(
        "SC-CMD-E1",
        "command",
        "command/edge_escapeshellcmd.php",
        "CWE-78",
        FINDING,
        J_FINDING,
    ),
    Fixture(
        "SC-CMD-E2", "command", "command/edge_static.php", "CWE-78", CLEAN, J_CLEAN
    ),
    # Code injection / SSTI (CWE-94/1336)
    Fixture("SC-CODE-P", "code", "code/vulnerable.php", "CWE-94", FINDING, J_FINDING),
    Fixture("SC-CODE-N", "code", "code/clean.php", "CWE-94", CLEAN, J_CLEAN),
    Fixture("SC-CODE-E1", "code", "code/edge_ssti.php", "CWE-1336", FINDING, J_FINDING),
    Fixture(
        "SC-CODE-E2", "code", "code/edge_static_eval.php", "CWE-94", CLEAN, J_CLEAN
    ),
    # Insecure deserialization (CWE-502)
    Fixture(
        "SC-DESER-P",
        "deserialization",
        "deserialization/vulnerable.php",
        "CWE-502",
        FINDING,
        J_FINDING,
    ),
    Fixture(
        "SC-DESER-N",
        "deserialization",
        "deserialization/clean.php",
        "CWE-502",
        CLEAN,
        J_CLEAN,
    ),
    Fixture(
        "SC-DESER-E1",
        "deserialization",
        "deserialization/edge_allowed_classes.php",
        "CWE-502",
        FINDING,
        J_FINDING,
    ),
    Fixture(
        "SC-DESER-E2",
        "deserialization",
        "deserialization/edge_static.php",
        "CWE-502",
        CLEAN,
        J_CLEAN,
    ),
    # SSRF (CWE-918)
    Fixture("SC-SSRF-P", "ssrf", "ssrf/vulnerable.php", "CWE-918", FINDING, J_FINDING),
    Fixture("SC-SSRF-N", "ssrf", "ssrf/clean.php", "CWE-918", CLEAN, J_CLEAN),
    Fixture(
        "SC-SSRF-E1",
        "ssrf",
        "ssrf/edge_scheme_only.php",
        "CWE-918",
        FINDING,
        J_FINDING,
    ),
    Fixture(
        "SC-SSRF-E2",
        "ssrf",
        "ssrf/edge_constant_url.php",
        "CWE-918",
        CLEAN,
        J_CLEAN,
    ),
    # Path traversal (CWE-22)
    Fixture("SC-PATH-P", "path", "path/vulnerable.php", "CWE-22", FINDING, J_FINDING),
    Fixture("SC-PATH-N", "path", "path/clean.php", "CWE-22", CLEAN, J_CLEAN),
    Fixture(
        "SC-PATH-E1", "path", "path/edge_include.php", "CWE-22", FINDING, J_FINDING
    ),
    Fixture(
        "SC-PATH-E2",
        "path",
        "path/edge_basename_only.php",
        "CWE-22",
        FINDING,
        J_FINDING,
    ),
    # XSS (CWE-79)
    Fixture("SC-XSS-P", "xss", "xss/vulnerable.php", "CWE-79", FINDING, J_FINDING),
    Fixture("SC-XSS-N", "xss", "xss/clean.php", "CWE-79", CLEAN, J_CLEAN),
    Fixture("SC-XSS-E1", "xss", "xss/edge_raw_twig.php", "CWE-79", FINDING, J_FINDING),
    Fixture("SC-XSS-E2", "xss", "xss/edge_intval.php", "CWE-79", CLEAN, J_CLEAN),
    # Open redirect (CWE-601)
    Fixture(
        "SC-REDIR-P",
        "redirect",
        "redirect/vulnerable.php",
        "CWE-601",
        FINDING,
        J_FINDING,
    ),
    Fixture("SC-REDIR-N", "redirect", "redirect/clean.php", "CWE-601", CLEAN, J_CLEAN),
    Fixture(
        "SC-REDIR-E1",
        "redirect",
        "redirect/edge_relative_only.php",
        "CWE-601",
        FINDING,
        J_FINDING,
    ),
    Fixture(
        "SC-REDIR-E2",
        "redirect",
        "redirect/edge_constant.php",
        "CWE-601",
        CLEAN,
        J_CLEAN,
    ),
    # Weak crypto (CWE-327/326)
    Fixture(
        "SC-CRYPTO-P", "crypto", "crypto/vulnerable.php", "CWE-327", FINDING, J_FINDING
    ),
    Fixture("SC-CRYPTO-N", "crypto", "crypto/clean.php", "CWE-327", CLEAN, J_CLEAN),
    Fixture(
        "SC-CRYPTO-E1", "crypto", "crypto/edge_sha1.php", "CWE-327", FINDING, J_FINDING
    ),
    Fixture(
        "SC-CRYPTO-E2",
        "crypto",
        "crypto/edge_md5_checksum.php",
        "CWE-327",
        CLEAN,
        J_CLEAN,
    ),
    # Hardcoded secret (CWE-798)
    Fixture(
        "SC-SECRET-P", "secret", "secret/vulnerable.php", "CWE-798", FINDING, J_FINDING
    ),
    Fixture("SC-SECRET-N", "secret", "secret/clean.php", "CWE-798", CLEAN, J_CLEAN),
    Fixture(
        "SC-SECRET-E1", "secret", "secret/edge_empty.php", "CWE-798", CLEAN, J_CLEAN
    ),
    Fixture(
        "SC-SECRET-E2",
        "secret",
        "secret/edge_config_default.php",
        "CWE-798",
        CLEAN,
        J_CLEAN,
    ),
    # XXE (CWE-611)
    Fixture("SC-XXE-P", "xxe", "xxe/vulnerable.php", "CWE-611", FINDING, J_FINDING),
    Fixture("SC-XXE-N", "xxe", "xxe/clean.php", "CWE-611", CLEAN, J_CLEAN),
    Fixture(
        "SC-XXE-E1",
        "xxe",
        "xxe/edge_simplexml_noent.php",
        "CWE-611",
        FINDING,
        J_FINDING,
    ),
    Fixture(
        "SC-XXE-E2", "xxe", "xxe/edge_default_flags.php", "CWE-611", CLEAN, J_CLEAN
    ),
)


# --- Logic families (judge lane only — no sound static signature) ----------
_LOGIC_FIXTURES: tuple[Fixture, ...] = (
    Fixture("JC-BOLA-P", "bola", "bola/vulnerable.php", "CWE-639", None, J_FINDING),
    Fixture("JC-BOLA-N", "bola", "bola/clean.php", "CWE-639", None, J_CLEAN),
    Fixture(
        "JC-BOLA-E1",
        "bola",
        "bola/edge_wrong_subject.php",
        "CWE-639",
        None,
        J_FINDING,
    ),
    Fixture("JC-BFLA-P", "bfla", "bfla/vulnerable.php", "CWE-285", None, J_FINDING),
    Fixture("JC-BFLA-N", "bfla", "bfla/clean.php", "CWE-285", None, J_CLEAN),
    Fixture("JC-BOPLA-P", "bopla", "bopla/vulnerable.php", "CWE-915", None, J_FINDING),
    Fixture("JC-BOPLA-N", "bopla", "bopla/clean.php", "CWE-915", None, J_CLEAN),
    Fixture("JC-AUTH-P", "auth", "auth/vulnerable.php", "CWE-287", None, J_FINDING),
    Fixture("JC-AUTH-N", "auth", "auth/clean.php", "CWE-287", None, J_CLEAN),
    Fixture("JC-RATE-P", "rate", "rate/vulnerable.php", "CWE-770", None, J_FINDING),
    Fixture("JC-RATE-N", "rate", "rate/clean.php", "CWE-770", None, J_CLEAN),
    Fixture("NC-NA-MOBILE", "na", "na/mobile_note.php", "N/A", None, J_NA),
    Fixture("NC-NA-MEMSAFE", "na", "na/memsafe_note.php", "N/A", None, J_NA),
)


FIXTURES: tuple[Fixture, ...] = _STATIC_FIXTURES + _LOGIC_FIXTURES

DEP_CASES: tuple[DepCase, ...] = (
    DepCase("SC-DEP-P", "deps/vulnerable.composer.json", "guzzlehttp/guzzle", True),
    DepCase("SC-DEP-N", "deps/clean.composer.json", "guzzlehttp/guzzle", False),
)


def static_fixtures() -> list[Fixture]:
    """Fixtures the static lane asserts (``static_expect`` is not None)."""
    return [f for f in FIXTURES if f.static_expect is not None]


def judge_fixtures() -> list[Fixture]:
    """Every fixture has a judge-lane expectation."""
    return list(FIXTURES)


def families() -> list[str]:
    """The sorted, de-duplicated set of dispatch families in the corpus."""
    return sorted({f.family for f in FIXTURES})
