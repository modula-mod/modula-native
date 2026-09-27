from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "build_nodus_02a1_reports.py"
SPEC = importlib.util.spec_from_file_location("build_nodus_02a1_reports", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Nodus02A1ReportTests(unittest.TestCase):
    def record(self) -> dict:
        return {
            "messageID": "answer-1",
            "developerRating": "wrong",
            "correction": "Use supplied evidence.",
            "failureTaxonomy": ["knowledge_grounding_failure"],
            "rootCause": "MODEL",
            "thinkEnabled": True,
            "thinkComparison": "worse",
            "knowledgeGrounding": {
                "retrievedFactCorrect": True,
                "finalAnswerCorrect": False,
                "followsEvidence": False,
            },
            "memoryAssessment": {
                "relevant": True,
                "scopeLeakage": False,
                "personalizationUseful": True,
            },
            "searchGrounding": {
                "retrievalCorrect": True,
                "synthesisFaithful": False,
                "unsupportedClaimsAdded": True,
                "citationFidelity": True,
            },
            "latency": {"generationSeconds": 1.5, "searchSeconds": 0.4, "inferencePasses": 3},
            "physical": {"scenarioID": "full-mode-01", "category": "full-mode"},
        }

    def test_builds_all_required_reports(self) -> None:
        reports = MODULE.build_reports([self.record()])
        self.assertEqual(set(reports), set(MODULE.REPORT_FILES))
        self.assertIn("Knowledge Grounding Failure", reports["failure"])
        self.assertIn("Worse: 1", reports["think"])
        self.assertIn("Unsupported claims added: 1/1", reports["search"])
        self.assertIn("Synthesis failures after correct retrieval: 1", reports["knowledge"])
        self.assertIn("Scope leakage: 0", reports["memory"])
        self.assertIn("knowledge_grounding_failure: 1", reports["r8"])

    def test_default_minimum_prevents_empty_evidence_publication(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            records = Path(directory) / "records.jsonl"
            records.write_text("")
            self.assertEqual(MODULE.load_records(records), [])


if __name__ == "__main__":
    unittest.main()
