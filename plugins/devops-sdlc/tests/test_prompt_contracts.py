"""Detect shared safety-contract drift without removing standalone prompt context."""

from __future__ import annotations

import ast
import copy
import fcntl
import importlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

PLUGIN = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PLUGIN / "tests"))
REFERENCE = importlib.import_module("ledger_reference")
STORAGE = importlib.import_module("ledger_reference.storage")
if (
    pathlib.Path(REFERENCE.__file__).resolve()
    != PLUGIN / "tests/ledger_reference/__init__.py"
):
    raise ImportError("Unexpected ledger reference import path")
transaction = REFERENCE.transaction
_save = STORAGE._save
CONTRACTS = {
    "command": {
        "profile validation": "validate-profile --repo .",
        "attempt limit": "MAX_ITERATIONS=5",
        "preflight-only fallback": (
            "No fallback or replay is allowed after the invocation starts, "
            "times out or has uncertain effects."
        ),
        "terminal breaker": (
            "Never automatically reset counters or a tripped Ralph circuit breaker."
        ),
        "required gate": "Only PASSED satisfies a required gate.",
        "atomic reservation": (
            "The caller atomically validates state and persists count+1 "
            "with an active owner and token before execution."
        ),
        "delegate ownership": (
            "A delegate receives the same reservation and never increments again."
        ),
    },
    "skill": {
        "profile validation": "validate-profile --repo .",
        "status vocabulary": "Return PASSED, FAILED, SKIPPED or BLOCKED",
        "attempt limit": "persisted count is already 5, stop with FAILED",
        "terminal breaker": "never reset or clear it to retry.",
        "atomic reservation": (
            "persists count+1 with active owner/token under one lock before execution."
        ),
        "authorization scope": (
            "Reuse authorization only for its exact action, target, "
            "environment and resource scope;"
        ),
    },
    "agent": {
        "attempt limit": "MAX_ITERATIONS=5",
        "missing resume counter": (
            "resuming without its prior count, report BLOCKED instead of assuming zero."
        ),
        "terminal breaker": "Re-entry preserves both count and breaker state.",
        "atomic reservation": (
            "The caller must verify a real atomic host reservation primitive."
        ),
        "fifth attempt ownership": (
            "including attempt 5/5, subject to current stop/state checks."
        ),
        "exhausted budget": "a known count at five or more means FAILED",
        "caller stop": "a known caller stop means BLOCKED",
        "no double increment": "the agent never increments again.",
        "required gate": "Neither BLOCKED nor SKIPPED satisfies a required check.",
        "quality floor": (
            "Never suppress findings, add baseline exclusions, lower thresholds,"
        ),
    },
}


def contract_violations(text: str, kind: str) -> list[str]:
    normalized = " ".join(text.split())
    return [
        name for name, required in CONTRACTS[kind].items() if required not in normalized
    ]


class PromptContractTests(unittest.TestCase):
    def test_each_standalone_prompt_retains_shared_safety_contract(self):
        groups = {
            "command": (list((PLUGIN / "commands").glob("*.md")), 8),
            "agent": (list((PLUGIN / "agents").glob("*.md")), 7),
            "skill": (list((PLUGIN / "skills").glob("*/SKILL.md")), 14),
        }
        for kind, (paths, expected) in groups.items():
            self.assertEqual(len(paths), expected)
            for path in paths:
                with self.subTest(kind=kind, path=path.relative_to(PLUGIN)):
                    self.assertEqual(contract_violations(path.read_text(), kind), [])

    def test_both_routing_inventories_match_every_skill_description(self):
        descriptions = {}
        for path in (PLUGIN / "skills").glob("*/SKILL.md"):
            line = next(
                line
                for line in path.read_text().splitlines()
                if line.startswith("description:")
            )
            descriptions[path.parent.name] = json.loads(line.split(":", 1)[1].strip())
        for name in ("AI-AGENT-GUIDE.md", "SKILL-DECISION-GUIDE.md"):
            text = (PLUGIN / "skills" / name).read_text()
            entries = re.findall(
                r"^- \[([^]]+)\]\([^)]*/SKILL\.md\) — (.+)$", text, re.M
            )
            with self.subTest(guide=name):
                self.assertEqual(len(entries), len(descriptions))
                self.assertEqual(dict(entries), descriptions)

    def test_counter_and_status_drift_is_detected(self):
        command = (PLUGIN / "commands/do-sdlc.md").read_text()
        self.assertIn(
            "attempt limit",
            contract_violations(
                command.replace("MAX_ITERATIONS=5", "MAX_ITERATIONS=6"), "command"
            ),
        )
        skill = (PLUGIN / "skills/terraform-terraspace/SKILL.md").read_text()
        self.assertIn(
            "status vocabulary",
            contract_violations(
                skill.replace(
                    "Return PASSED, FAILED, SKIPPED or BLOCKED", "Return PASS or FAIL"
                ),
                "skill",
            ),
        )


REFERENCE_MODULES = (
    "__init__",
    "storage",
    "history",
    "state",
    "observation",
    "actions",
    "transaction",
)


def reference_sources(text):
    start = "<!-- atomic-ledger-reference:start -->"
    end = "<!-- atomic-ledger-reference:end -->"
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError("Missing or duplicate reference boundary")
    body = text.split(start, 1)[1].split(end, 1)[0]
    pattern = re.compile(
        r"<!-- atomic-ledger-module:ledger_reference/([a-z_]+)\.py -->\n"
        r"```python\n(.*?)```",
        re.S,
    )
    if pattern.sub("", body).strip():
        raise ValueError("Unrecognized reference content")
    return pattern.findall(body)


class ReferenceSourceTests(unittest.TestCase):
    def verify_reference(self, text):
        sources = reference_sources(text)
        self.assertEqual([name for name, _ in sources], list(REFERENCE_MODULES))
        for name, documented in sources:
            module_name = "ledger_reference" + (
                "." + name if name != "__init__" else ""
            )
            imported = importlib.import_module(module_name)
            expected = PLUGIN / "tests/ledger_reference" / (name + ".py")
            self.assertEqual(
                pathlib.Path(imported.__file__).resolve(), expected.resolve()
            )
            checked_in = expected.read_text(encoding="utf-8")
            self.assertEqual(documented, checked_in)
            self.assertEqual(
                ast.dump(ast.parse(documented)), ast.dump(ast.parse(checked_in))
            )

    def test_absolute_loader_works_without_test_directory_on_search_path(self):
        code = "\n".join(
            (
                "import importlib.util, pathlib, sys",
                "path = pathlib.Path(sys.argv[1])",
                "assert str(path.parent) not in sys.path",
                "spec = importlib.util.spec_from_file_location('isolated', path)",
                "module = importlib.util.module_from_spec(spec)",
                "spec.loader.exec_module(module)",
                "assert module.PromptContractTests.__name__ == 'PromptContractTests'",
                "expected = path.parent / 'ledger_reference/__init__.py'",
                "assert pathlib.Path(module.REFERENCE.__file__).resolve() == expected",
                "assert module.transaction is module.REFERENCE.transaction",
            )
        )
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [
                    sys.executable,
                    "-I",
                    "-c",
                    code,
                    str(pathlib.Path(__file__).resolve()),
                ],
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fences_exactly_match_imported_reviewed_modules(self):
        self.verify_reference((PLUGIN / "docs/atomic-ledger-reference.md").read_text())

    def test_changed_markdown_is_rejected_without_execution(self):
        text = (PLUGIN / "docs/atomic-ledger-reference.md").read_text()
        cases = (
            text.replace(
                'return {"decision": "START_ONCE", **active}',
                'raise RuntimeError("never execute Markdown")',
            ),
            text.replace(
                "atomic-ledger-module:ledger_reference/storage.py",
                "atomic-ledger-module:ledger_reference/unreviewed.py",
            ),
            text.replace("atomic-ledger-reference:end", "missing-reference-end"),
            text.replace(
                "<!-- atomic-ledger-reference:end -->",
                '```python\nraise RuntimeError("unreviewed")\n```\n'
                "<!-- atomic-ledger-reference:end -->",
            ),
        )
        for changed in cases:
            with self.subTest(changed=changed[-80:]):
                with self.assertRaises((AssertionError, ValueError)):
                    self.verify_reference(changed)


class AtomicLedgerReferenceTests(unittest.TestCase):
    """Execute imported reviewed code against isolated ledger fixtures."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = pathlib.Path(self.temp.name)
        self.api = {"transaction": transaction, "_save": _save, "fcntl": fcntl}
        self.directory = os.open(self.path, os.O_RDONLY | os.O_DIRECTORY)
        self.addCleanup(os.close, self.directory)
        self.identity = [
            "fixture",
            "do-sdlc-qa",
            "qa-infrastructure-tester",
            "app",
            "dev",
        ]
        self.request = {"owner": "caller-session"}
        self.observation = {
            "verified": True,
            "evidence": "inert host observation",
            "caller_stop": False,
            "caller_stop_evidence": None,
            "breaker": "clear",
            "ralph": "none",
            "ralph_evidence": None,
        }

    def observe(self, identity, _entry):
        return {"identity": identity, **self.observation}

    def call(self, action, **fields):
        callback = fields.pop("callback", self.observe)
        return self.api["transaction"](
            self.directory,
            self.identity,
            {**self.request, "action": action, **fields},
            callback,
        )

    def initialize(self):
        result = self.call("initialize", verified_new_task_reference="inert proof")
        self.assertEqual(result["decision"], "INITIALIZED")

    def read_entry(self):
        data = json.loads((self.path / "attempts.json").read_text())
        return data, next(iter(data["entries"].values()))

    def test_documented_fifth_attempt_is_owned_and_no_sixth_can_start(self):
        self.initialize()
        for count in range(1, 6):
            reserved = self.call("reserve")
            self.assertEqual(reserved["decision"], "RESERVED")
            self.assertEqual(reserved["attempt"], count)
            token = reserved["token"]
            before = (self.path / "attempts.json").read_bytes()
            observed = self.call("observe", token=token)
            self.assertEqual(observed["decision"], "OBSERVE_ONLY")
            self.assertEqual(observed["phase"], "reserved")
            self.assertEqual((self.path / "attempts.json").read_bytes(), before)
            self.assertEqual(
                self.call("observe", token=token, owner="other-session")["decision"],
                "BLOCKED",
            )
            self.assertEqual(self.call("start", token=token)["decision"], "START_ONCE")
            self.assertEqual(self.call("start", token=token)["decision"], "BLOCKED")
            self.assertEqual(
                self.call("observe", token=token)["decision"], "OBSERVE_ONLY"
            )
            self.assertEqual(self.call("finish", token=token)["decision"], "BLOCKED")
            result = self.call(
                "finish",
                token=token,
                outcome="FAILED",
                evidence="fixture outcome",
                no_pending_verified=True,
            )
            self.assertEqual(result["decision"], "RECORDED")
        self.assertEqual(self.call("reserve")["decision"], "FAILED")
        _, entry = self.read_entry()
        self.assertEqual(entry["count"], 5)
        self.assertEqual(len(entry["history"]), 5)
        self.assertIsNone(entry["active"])
        before = (self.path / "attempts.json").read_bytes()
        self.identity[2] = "replacement-agent"
        for action in ("initialize", "reserve", "start"):
            result = self.call(action, verified_new_task_reference="new claim")
            self.assertEqual(result["decision"], "BLOCKED")
            self.assertEqual((self.path / "attempts.json").read_bytes(), before)

    def test_new_agent_cannot_initialize_or_use_the_same_budget(self):
        self.initialize()
        original = list(self.identity)
        for phase in range(2):
            token = self.call("reserve")["token"] if phase else None
            self.identity = [*original[:2], "other-agent", *original[3:]]
            before = (self.path / "attempts.json").read_bytes()
            for action in ("initialize", "reserve", "start", "observe", "finish"):
                with self.subTest(action=action, token=token):
                    result = self.call(
                        action, token=token, verified_new_task_reference="new claim"
                    )
                    self.assertEqual(result["decision"], "BLOCKED")
                    self.assertEqual((self.path / "attempts.json").read_bytes(), before)
            self.identity = original
        self.assertEqual(self.read_entry()[1]["count"], 1)

    def test_existing_conflicting_agents_block_both_sides_without_history_changes(self):
        self.initialize()
        data, entry = self.read_entry()
        other = [*self.identity[:2], "other-agent", *self.identity[3:]]
        data["entries"][json.dumps(other, separators=(",", ":"))] = copy.deepcopy(entry)
        self.api["_save"](self.directory, data)
        before = (self.path / "attempts.json").read_bytes()
        for identity in (self.identity, other):
            self.identity = identity
            for action in ("initialize", "reserve", "start", "observe", "finish"):
                result = self.call(action, verified_new_task_reference="new claim")
                self.assertEqual(result["decision"], "BLOCKED")
                self.assertEqual((self.path / "attempts.json").read_bytes(), before)

    def test_budget_identity_schema_is_validated_before_admission(self):
        self.initialize()
        original, entry = self.read_entry()
        for key in (
            "not-json",
            "null",
            "[1]",
            json.dumps(self.identity),
            json.dumps(["other-task", *self.identity[1:]], separators=(",", ":")),
        ):
            with self.subTest(key=key):
                data = copy.deepcopy(original)
                data["entries"][key] = copy.deepcopy(entry)
                self.api["_save"](self.directory, data)
                before = (self.path / "attempts.json").read_bytes()
                self.assertEqual(self.call("reserve")["decision"], "BLOCKED")
                self.assertEqual((self.path / "attempts.json").read_bytes(), before)

    def test_distinct_stage_target_and_environment_keep_separate_budgets(self):
        self.initialize()
        original = list(self.identity)
        for position in (1, 3, 4):
            self.identity = list(original)
            self.identity[position] += "-separate"
            self.identity[2] = "other-agent"
            self.initialize()
            self.assertEqual(self.call("reserve")["attempt"], 1)
        data, _ = self.read_entry()
        self.assertEqual(len(data["entries"]), 4)

    def test_hard_kill_snapshot_is_retained_and_blocks_transaction(self):
        self.initialize()
        before = (self.path / "attempts.json").read_bytes()
        code = "\n".join(
            (
                "import json, os, signal, sys",
                "from ledger_reference import transaction",
                "from ledger_reference import storage",
                "def kill_before_replace(*args, **kwargs):",
                "    os.kill(os.getpid(), signal.SIGKILL)",
                "storage.os.replace = kill_before_replace",
                "directory = os.open(sys.argv[1], os.O_RDONLY | os.O_DIRECTORY)",
                "identity = json.loads(sys.argv[2])",
                "def observed(current, entry):",
                "    return dict(entry, verified=True, evidence='host', "
                "identity=current)",
                "request = {'owner':'child', 'action':'reserve'}",
                "transaction(directory, identity, request, observed)",
            )
        )
        result = subprocess.run(
            [sys.executable, "-c", code, str(self.path), json.dumps(self.identity)],
            env={**os.environ, "PYTHONPATH": str(PLUGIN / "tests")},
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        self.assertEqual(result.returncode, -9, result.stderr)
        leftovers = list(self.path.glob(".attempts-*"))
        self.assertEqual(len(leftovers), 1)
        snapshot = leftovers[0].read_bytes()
        self.assertEqual(self.call("reserve")["decision"], "BLOCKED")
        self.assertEqual(leftovers[0].read_bytes(), snapshot)
        self.assertEqual((self.path / "attempts.json").read_bytes(), before)

    def test_live_lock_conflict_and_persisted_owner_prevent_double_reservation(self):
        self.initialize()
        lock = os.open(self.path / "attempts.lock", os.O_RDWR)
        try:
            self.api["fcntl"].flock(lock, self.api["fcntl"].LOCK_EX)
            self.assertEqual(self.call("reserve")["decision"], "BLOCKED")
        finally:
            os.close(lock)
        reserved = self.call("reserve")
        self.assertEqual(
            self.call("reserve", owner="competing-session")["decision"], "BLOCKED"
        )
        self.assertEqual(
            self.call("start", token=reserved["token"], owner="competing-session")[
                "decision"
            ],
            "BLOCKED",
        )
        _, entry = self.read_entry()
        self.assertEqual(entry["count"], 1)
        self.assertEqual(entry["active"]["token"], reserved["token"])

    def test_missing_sidecar_never_resets_historical_markdown_count(self):
        (self.path / "run-summary.md").write_text(
            "Recorded count 4/5; prior run uncertain"
        )
        self.assertEqual(self.call("reserve")["decision"], "BLOCKED")
        self.assertEqual(
            self.call("initialize", verified_new_task_reference="incorrect new claim")[
                "decision"
            ],
            "BLOCKED",
        )
        self.assertFalse((self.path / "attempts.json").exists())

    def test_status_precedence_preserves_stop_and_incomplete_history(self):
        self.initialize()
        data, entry = self.read_entry()
        baseline = dict(entry)
        for fields, expected in (
            ({"count": 5, "caller_stop": True, "breaker": None}, "FAILED"),
            ({"caller_stop": True, "breaker": None}, "BLOCKED"),
            ({"breaker": "tripped", "ralph_evidence": "actual log"}, "FAILED"),
            ({"breaker": "tripped", "ralph_evidence": None}, "BLOCKED"),
            ({"count": None}, "BLOCKED"),
            ({"ralph": "pending"}, "BLOCKED"),
        ):
            with self.subTest(fields=fields):
                entry.clear()
                entry.update({**baseline, **fields})
                self.api["_save"](self.directory, data)
                self.assertEqual(self.call("reserve")["decision"], expected)
        for path in (PLUGIN / "agents").glob("*.md"):
            self.assertNotIn("ESCALATED", path.read_text())

    def test_current_observation_under_lock_blocks_start_and_retains_stop(self):
        self.initialize()
        reserved = self.call("reserve")
        self.observation.update(
            caller_stop=True, caller_stop_evidence="new caller halt"
        )
        calls = []

        def inspect(identity, entry):
            lock = os.open(self.path / "attempts.lock", os.O_RDWR)
            try:
                with self.assertRaises(BlockingIOError):
                    self.api["fcntl"].flock(
                        lock, self.api["fcntl"].LOCK_EX | self.api["fcntl"].LOCK_NB
                    )
            finally:
                os.close(lock)
            calls.append(identity)
            return self.observe(identity, entry)

        self.assertEqual(
            self.call("start", token=reserved["token"], callback=inspect)["decision"],
            "BLOCKED",
        )
        self.assertEqual(calls, [self.identity])
        _, entry = self.read_entry()
        self.assertTrue(entry["caller_stop"])
        self.assertEqual(entry["caller_stop_evidence"], "new caller halt")
        self.assertEqual(entry["active"]["phase"], "reserved")
        self.observation.update(caller_stop=False, caller_stop_evidence=None)
        self.assertEqual(
            self.call("start", token=reserved["token"])["decision"], "BLOCKED"
        )
        self.assertTrue(self.read_entry()[1]["caller_stop"])

    def test_absent_unverified_or_throwing_observer_cannot_reserve(self):
        self.initialize()
        before = (self.path / "attempts.json").read_bytes()

        def broken(_identity, _entry):
            raise RuntimeError("host observation failed")

        for callback in (None, broken, lambda *_: {"verified": False}):
            with self.subTest(callback=callback):
                self.assertEqual(
                    self.call("reserve", callback=callback)["decision"], "BLOCKED"
                )
                self.assertEqual((self.path / "attempts.json").read_bytes(), before)

    def test_malformed_active_history_is_never_retired(self):
        self.initialize()
        token = self.call("reserve")["token"]
        data, _ = self.read_entry()
        cases = [
            lambda e: e["active"].update(phase="finished"),
            lambda e: e["active"].update(attempt=True),
            lambda e: e["active"].update(attempt=0),
            lambda e: e["active"].update(attempt=6),
            lambda e: e.update(count=True),
            lambda e: e["active"].update(owner=" "),
            lambda e: e["active"].update(token="z" * 32),
            lambda e: e["history"].append({"attempt": 1}),
        ]
        for mutate in cases:
            changed = copy.deepcopy(data)
            entry = next(iter(changed["entries"].values()))
            mutate(entry)
            self.api["_save"](self.directory, changed)
            before = (self.path / "attempts.json").read_bytes()
            self.assertEqual(
                self.call(
                    "finish",
                    token=token,
                    outcome="FAILED",
                    evidence="fixture",
                    no_pending_verified=True,
                )["decision"],
                "BLOCKED",
            )
            self.assertEqual((self.path / "attempts.json").read_bytes(), before)

    def test_invalid_initialization_and_boolean_schema_preserve_data(self):
        for reference in (True, {}, [], 1, "", " "):
            self.assertEqual(
                self.call("initialize", verified_new_task_reference=reference)[
                    "decision"
                ],
                "BLOCKED",
            )
            self.assertFalse((self.path / "attempts.json").exists())
        self.initialize()
        data, _ = self.read_entry()
        data["schema_version"] = True
        self.api["_save"](self.directory, data)
        before = (self.path / "attempts.json").read_bytes()
        with self.assertRaises(ValueError):
            self.call("initialize", verified_new_task_reference="fixture")
        self.assertEqual((self.path / "attempts.json").read_bytes(), before)

    def test_duplicate_keys_at_any_depth_preserve_exact_ledger_bytes(self):
        self.initialize()
        self.call("reserve")
        raw = (self.path / "attempts.json").read_text()
        for original, duplicate in (
            ('"count": 1', '"count": 5, "count": 1'),
            ('"task_id": "fixture"', '"task_id": "other", "task_id": "fixture"'),
            ('"entries": {', '"entries": {}, "entries": {'),
        ):
            self.assertIn(original, raw)
            changed = raw.replace(original, duplicate, 1)
            (self.path / "attempts.json").write_text(changed)
            with self.assertRaisesRegex(ValueError, "Duplicate ledger key"):
                self.call("reserve")
            self.assertEqual((self.path / "attempts.json").read_text(), changed)

    def test_invalid_saved_state_blocks_before_current_observation(self):
        self.initialize()
        original, _ = self.read_entry()
        cases = [
            ("caller_stop", None),
            ("caller_stop", "false"),
            ("breaker", None),
            ("breaker", "unknown"),
            ("ralph", None),
            ("ralph", "unknown"),
            ("ralph_evidence", None),
            ("ralph_evidence", " "),
        ]
        for field, value in cases:
            for missing in (True, False):
                with self.subTest(field=field, missing=missing, value=value):
                    data = copy.deepcopy(original)
                    entry = next(iter(data["entries"].values()))
                    if field == "ralph_evidence":
                        entry["ralph"] = "completed"
                    if missing:
                        entry.pop(field, None)
                    else:
                        entry[field] = value
                    self.api["_save"](self.directory, data)
                    before = (self.path / "attempts.json").read_bytes()
                    calls = []

                    def fresh(identity, entry):
                        calls.append(identity)
                        return self.observe(identity, entry)

                    self.assertEqual(
                        self.call("reserve", callback=fresh)["decision"], "BLOCKED"
                    )
                    self.assertEqual(calls, [])
                    self.assertEqual((self.path / "attempts.json").read_bytes(), before)

    def test_lost_run_observation_keeps_prior_reference_and_can_be_resolved(self):
        self.initialize()
        data, entry = self.read_entry()
        entry.update(ralph="completed", ralph_evidence="original run log")
        self.api["_save"](self.directory, data)
        self.assertEqual(self.call("reserve")["decision"], "BLOCKED")
        _, saved = self.read_entry()
        self.assertEqual(saved["ralph"], "completed")
        self.assertEqual(saved["ralph_evidence"], "original run log")
        self.assertEqual(saved["count"], 0)
        self.assertTrue(saved["observation_blocked"])
        self.observation.update(
            ralph="completed", ralph_evidence="verified completion log"
        )
        self.assertEqual(self.call("reserve")["decision"], "RESERVED")
        self.assertEqual(
            self.read_entry()[1]["ralph_evidence"], "verified completion log"
        )

    def test_valid_pending_state_can_resolve_through_verified_callback(self):
        self.initialize()
        original, _ = self.read_entry()
        self.observation.update(
            ralph="completed", ralph_evidence="verified terminal log"
        )
        for state in ("active", "pending", "uncertain"):
            with self.subTest(state=state):
                data = copy.deepcopy(original)
                entry = next(iter(data["entries"].values()))
                entry.update(ralph=state, ralph_evidence="existing run reference")
                self.api["_save"](self.directory, data)
                self.assertEqual(self.call("reserve")["decision"], "RESERVED")
                self.assertEqual(self.read_entry()[1]["ralph"], "completed")

    def test_active_marker_and_atomic_contract_removal_is_detected(self):
        for kind, path, needle in (
            ("command", "commands/do-sdlc-qa.md", "active owner"),
            ("agent", "agents/qa-infrastructure-tester.md", "real atomic host"),
            ("skill", "skills/terraform-terraspace/SKILL.md", "active owner/token"),
        ):
            text = (PLUGIN / path).read_text()
            self.assertEqual(contract_violations(text, kind), [])
            self.assertIn(
                "atomic reservation",
                contract_violations(text.replace(needle, "counter"), kind),
            )


if __name__ == "__main__":
    unittest.main()
