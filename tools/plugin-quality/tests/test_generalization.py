"""Self-tests for check_generalization (L28-L29 / GN-1, GN-2).

Synthetic plugin trees are built at runtime in a temp dir; NO committed
fixtures, and nothing on disk in the repo carries a denylisted token — the
forbidden identifiers are assembled from string literals here and written into
temp files only. The real shipped plugin is also scanned and must be clean
(ci.yml's generalization-audit passes today).
"""

import pathlib
import shutil
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import check_generalization  # noqa: E402

REPO_ROOT = HERE.parent.parent.parent
REAL_PLUGIN = REPO_ROOT / "plugins" / "php-backend-sdlc"

# Assemble denylisted tokens from fragments so this source file itself stays
# clean of the literal forbidden identifiers.
TOK_MONGO_REPO = "Mongo" + "User" + "Repository"  # mongo<word>repository
TOK_USER_SERVICE = "user" + "-" + "service"  # user[-_ ]service


class GeneralizationCase(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        # Mirror <repo>/plugins/<name> so rel() yields repo-relative paths.
        self.root = self.tmp / "plugins" / "p"
        for sub in ("skills", "commands", "agents", "scripts"):
            (self.root / sub).mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write_skill(self, name, text):
        d = self.root / "skills" / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "SKILL.md").write_text(text, encoding="utf-8")

    def _findings(self, check_id=None):
        fs = check_generalization.check(self.root)
        if check_id is not None:
            fs = [f for f in fs if f.check == check_id]
        return fs

    # --- GN-1 (L28) denylist ---------------------------------------------

    def test_gn1_clean_tree_passes(self):
        self._write_skill(
            "s",
            "---\nname: s\n---\n\n# Skill\n\nUses the configured repository.\n",
        )
        self.assertEqual(self._findings("L28"), [])

    def test_gn1_mongo_repository_in_skill_body_fails_s1(self):
        body = f"---\nname: s\n---\n\n# Skill\n\nInjects {TOK_MONGO_REPO} directly.\n"
        self._write_skill("s", body)
        fs = self._findings("L28")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "generalization.denylist")
        self.assertEqual(fs[0].severity, "S1")
        self.assertEqual(fs[0].line, 7)

    def test_gn1_user_service_in_prose_fails(self):
        body = f"---\nname: s\n---\n\n# Skill\n\nBoot the {TOK_USER_SERVICE} container.\n"
        self._write_skill("s", body)
        fs = self._findings("L28")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].severity, "S1")

    def test_gn1_token_inside_profile_example_fence_is_stripped(self):
        # Same forbidden token, but inside a ```bash # profile-example fence.
        body = (
            "---\nname: s\n---\n\n# Skill\n\n"
            "```bash # profile-example\n"
            f"docker compose exec {TOK_USER_SERVICE} sh\n"
            "```\n\n"
            "Generic prose with no leak.\n"
        )
        self._write_skill("s", body)
        self.assertEqual(self._findings("L28"), [])

    def test_gn1_token_outside_fence_still_caught_after_strip(self):
        # A profile-example fence is stripped, but a leak in surrounding prose
        # must still be reported with the correct (post-strip) line number.
        body = (
            "---\nname: s\n---\n\n# Skill\n\n"
            "```bash # profile-example\n"
            f"docker compose exec {TOK_USER_SERVICE} sh\n"
            "```\n\n"
            f"But this {TOK_MONGO_REPO} mention leaks.\n"
        )
        self._write_skill("s", body)
        fs = self._findings("L28")
        self.assertEqual(len(fs), 1)
        # Line numbers stay aligned to the original file (strip yields None
        # placeholders, not deleted lines): the leak is the 11th source line.
        self.assertEqual(fs[0].line, 11)

    def test_gn1_scoped_to_known_extensions_and_dirs(self):
        # A leak in a non-scanned extension (.txt) under a scoped dir is ignored.
        (self.root / "skills" / "note.txt").write_text(
            f"{TOK_USER_SERVICE}\n", encoding="utf-8"
        )
        self.assertEqual(self._findings("L28"), [])

    def test_gn1_tilde_profile_example_fence_not_stripped(self):
        # Fix 5: ci.yml's awk only recognizes backtick fences, so a tilde fence
        # carrying '# profile-example' is NOT stripped — the Python gate must
        # match CI exactly and still flag the leak inside it.
        body = (
            "---\nname: s\n---\n\n# Skill\n\n"
            "~~~bash # profile-example\n"
            f"docker compose exec {TOK_USER_SERVICE} sh\n"
            "~~~\n\n"
            "Generic prose with no leak.\n"
        )
        self._write_skill("s", body)
        fs = self._findings("L28")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].severity, "S1")
        # The leak is the docker line inside the (unstripped) tilde fence.
        self.assertEqual(fs[0].line, 8)

    def test_gn1_backtick_profile_example_still_stripped(self):
        # Fix 5 control: backtick profile-example fences remain stripped.
        body = (
            "---\nname: s\n---\n\n# Skill\n\n"
            "```bash # profile-example\n"
            f"docker compose exec {TOK_USER_SERVICE} sh\n"
            "```\n\n"
            "Generic prose with no leak.\n"
        )
        self._write_skill("s", body)
        self.assertEqual(self._findings("L28"), [])

    # --- GN-2 (L29) tree hygiene -----------------------------------------

    def test_gn2_no_stray_dirs_passes(self):
        self._write_skill("s", "---\nname: s\n---\n\n# Skill\n\nclean\n")
        self.assertEqual(self._findings("L29"), [])

    def test_gn2_bmad_dir_fails_s1(self):
        (self.root / "_bmad").mkdir(parents=True, exist_ok=True)
        (self.root / "_bmad" / "x.md").write_text("vendored\n", encoding="utf-8")
        fs = self._findings("L29")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "generalization.tree-hygiene")
        self.assertEqual(fs[0].severity, "S1")
        self.assertTrue(fs[0].path.endswith("_bmad"))

    def test_gn2_ralph_dir_fails(self):
        (self.root / ".ralph").mkdir(parents=True, exist_ok=True)
        fs = self._findings("L29")
        self.assertEqual(len(fs), 1)
        self.assertTrue(fs[0].path.endswith(".ralph"))

    def test_gn2_bmad_substring_filename_not_flagged(self):
        # "notes_bmad.md" merely CONTAINS the substring; it is not an exact
        # _bmad component, so it must not be flagged.
        (self.root / "skills" / "notes_bmad.md").write_text(
            "# clean\n", encoding="utf-8"
        )
        self.assertEqual(self._findings("L29"), [])

    # --- real shipped plugin is clean ------------------------------------

    def test_real_plugin_clean(self):
        self.assertTrue(REAL_PLUGIN.is_dir(), f"missing real plugin at {REAL_PLUGIN}")
        fs = check_generalization.check(REAL_PLUGIN)
        self.assertEqual(
            fs,
            [],
            "shipped plugin must be clean for L28-L29; got: "
            + "; ".join(f.render() for f in fs),
        )


if __name__ == "__main__":
    unittest.main()
