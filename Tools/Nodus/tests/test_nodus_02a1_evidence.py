from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "build_nodus_02a1_evidence.py"
SPEC = importlib.util.spec_from_file_location("build_nodus_02a1_evidence", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Nodus02A1EvidenceTests(unittest.TestCase):
    def conversation(self) -> dict:
        return {
            "schemaVersion": 1,
            "conversations": [{
                "id": "conversation-1",
                "attachedKnowledgeCollectionIDs": ["knowledge-1"],
                "messages": [
                    {"id": "user-1", "role": "user", "text": "What's Modula?", "createdAt": "2026-09-27T00:00:00Z"},
                    {
                        "id": "answer-1", "role": "nodus", "text": "Modula is independent.",
                        "createdAt": "2026-09-27T00:00:01Z",
                        "details": {
                            "reasoningMode": "deep", "searchEnabled": False,
                            "knowledgeChunkCount": 1, "memoryItemIDs": [], "inferencePasses": 3,
                        },
                        "answer": {
                            "modelVersion": "Nodus R7 Experimental", "freshness": "stable",
                            "confidence": {"band": "high"}, "latencySeconds": 0.5,
                            "tokensPerSecond": 20.0,
                        },
                        "citations": [{
                            "kind": "knowledge", "title": "Modula Core", "sourceName": "architecture.md",
                            "collectionName": "Modula Core", "location": "chunk 1",
                        }],
                    },
                ],
            }],
        }

    def test_builds_reviewed_record_with_required_metadata(self) -> None:
        reviews = [{
            "messageID": "answer-1", "developerRating": "good", "failureTaxonomy": [],
            "knowledgeGrounding": {
                "retrievedFactCorrect": True, "finalAnswerCorrect": True, "followsEvidence": True,
            },
            "thinkComparison": "better",
        }]
        capture = {"interactions": [{
            "id": "modula-01", "category": "modula",
            "thermalStateBefore": "nominal", "thermalStateAfter": "nominal",
            "batteryLevelBefore": 0.8, "batteryLevelAfter": 0.79,
            "response": {"id": "answer-1"},
        }]}
        records = MODULE.build_records(self.conversation(), [], reviews, capture)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["conversationID"], "conversation-1")
        self.assertTrue(records[0]["thinkEnabled"])
        self.assertEqual(records[0]["knowledgeChunksUsed"], 1)
        self.assertEqual(records[0]["modelHash"], MODULE.MODEL_HASH)
        self.assertEqual(records[0]["physical"]["category"], "modula")
        self.assertEqual(records[0]["thinkComparison"], "better")

    def test_requires_knowledge_grounding_diagnostic(self) -> None:
        reviews = [{"messageID": "answer-1", "developerRating": "good", "failureTaxonomy": []}]
        with self.assertRaisesRegex(ValueError, "knowledgeGrounding"):
            MODULE.build_records(self.conversation(), [], reviews)

    def test_requires_search_grounding_diagnostic(self) -> None:
        conversation = self.conversation()
        answer = conversation["conversations"][0]["messages"][1]
        answer["details"]["searchedWeb"] = True
        answer["citations"] = [{
            "kind": "web", "title": "Swift", "sourceName": "swift.org",
            "url": "https://swift.org/install", "retrievedAt": "2026-09-27T00:00:00Z",
        }]
        reviews = [{"messageID": "answer-1", "developerRating": "good", "failureTaxonomy": []}]
        with self.assertRaisesRegex(ValueError, "searchGrounding"):
            MODULE.build_records(conversation, [], reviews)

    def test_requires_memory_assessment(self) -> None:
        conversation = self.conversation()
        answer = conversation["conversations"][0]["messages"][1]
        answer["details"]["memoryItemIDs"] = ["memory-1"]
        reviews = [{
            "messageID": "answer-1", "developerRating": "good", "failureTaxonomy": [],
            "knowledgeGrounding": {
                "retrievedFactCorrect": True, "finalAnswerCorrect": True, "followsEvidence": True,
            },
        }]
        with self.assertRaisesRegex(ValueError, "memoryAssessment"):
            MODULE.build_records(conversation, [], reviews)

    def test_rejects_failed_rating_without_correction(self) -> None:
        reviews = [{
            "messageID": "answer-1", "developerRating": "wrong",
            "failureTaxonomy": ["modula_knowledge_error"], "rootCause": "MODEL",
            "knowledgeGrounding": {
                "retrievedFactCorrect": True, "finalAnswerCorrect": False, "followsEvidence": False,
            },
        }]
        with self.assertRaisesRegex(ValueError, "correction required"):
            MODULE.build_records(self.conversation(), [], reviews)

    def test_rejects_unknown_failure_taxonomy(self) -> None:
        reviews = [{
            "messageID": "answer-1", "developerRating": "wrong", "correction": "Correct",
            "failureTaxonomy": ["invented_failure"], "rootCause": "MODEL",
            "knowledgeGrounding": {
                "retrievedFactCorrect": True, "finalAnswerCorrect": False, "followsEvidence": False,
            },
        }]
        with self.assertRaisesRegex(ValueError, "invalid failure taxonomy"):
            MODULE.build_records(self.conversation(), [], reviews)

    def test_writes_deterministic_jsonl(self) -> None:
        reviews = [{
            "messageID": "answer-1", "developerRating": "good", "failureTaxonomy": [],
            "knowledgeGrounding": {
                "retrievedFactCorrect": True, "finalAnswerCorrect": True, "followsEvidence": True,
            },
        }]
        records = MODULE.build_records(self.conversation(), [], reviews)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "records.jsonl"
            MODULE.write_jsonl(records, output)
            decoded = json.loads(output.read_text().strip())
            self.assertEqual(decoded["messageID"], "answer-1")


if __name__ == "__main__":
    unittest.main()
