"""Tests for the corpus manifest (pure data + accessors)."""

import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import corpus  # noqa: E402


class TestCorpus(unittest.TestCase):
    def test_static_fixtures_all_have_expectation(self):
        sf = corpus.static_fixtures()
        self.assertTrue(sf)
        self.assertTrue(all(f.static_expect is not None for f in sf))

    def test_logic_fixtures_excluded_from_static(self):
        logic = [f for f in corpus.FIXTURES if f.static_expect is None]
        self.assertTrue(logic)
        static_cids = {f.cid for f in corpus.static_fixtures()}
        self.assertTrue(all(f.cid not in static_cids for f in logic))

    def test_judge_fixtures_is_every_fixture(self):
        self.assertEqual(len(corpus.judge_fixtures()), len(corpus.FIXTURES))

    def test_every_fixture_has_a_judge_verdict(self):
        valid = {corpus.J_FINDING, corpus.J_CLEAN, corpus.J_NA}
        self.assertTrue(all(f.judge_expect in valid for f in corpus.FIXTURES))

    def test_families_sorted_unique(self):
        fams = corpus.families()
        self.assertEqual(fams, sorted(set(fams)))
        self.assertIn("sqli", fams)
        self.assertIn("bola", fams)

    def test_fixture_paths_unique(self):
        paths = [f.path for f in corpus.FIXTURES]
        self.assertEqual(len(paths), len(set(paths)))

    def test_case_ids_unique(self):
        cids = [f.cid for f in corpus.FIXTURES]
        self.assertEqual(len(cids), len(set(cids)))

    def test_fixture_files_exist(self):
        corpus_dir = HERE.parent / "corpus"
        for f in corpus.FIXTURES:
            self.assertTrue(
                (corpus_dir / f.path).is_file(), f"missing fixture {f.path}"
            )

    def test_dep_cases_present_and_files_exist(self):
        corpus_dir = HERE.parent / "corpus"
        self.assertTrue(corpus.DEP_CASES)
        for dc in corpus.DEP_CASES:
            self.assertTrue((corpus_dir / dc.path).is_file())
            self.assertIn(dc.package, corpus.VULN_RANGES)


if __name__ == "__main__":
    unittest.main()
