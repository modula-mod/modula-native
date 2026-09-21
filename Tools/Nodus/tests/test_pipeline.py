import json
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from build_dataset import build
from build_model_manifest import build_manifest
from common import GovernanceError, sha256, validate_learning_candidate
from evaluate import is_abstention, score_case
from promotion_gate import evaluate_gates
from select_base import choose_base
from train import validate_config

SELECTED_BASE = "Qwen/Qwen3-1.7B"
SELECTED_REVISION = "70d244cc86ccca08cf5af4e1e306ecf908b1ad5e"


class DatasetPipelineTests(unittest.TestCase):
    def test_base_selection_requires_equal_completed_reports_and_prefers_general(self):
        catalog = json.loads((ROOT / "licenses/base-models.json").read_text())
        qwen = {
            "model": "Qwen/Qwen3-1.7B",
            "revision": "70d244cc86ccca08cf5af4e1e306ecf908b1ad5e",
            "adapter": None,
            "scores": {"general": 1.0, "freshness": 0.8, "uncertainty": 1.0, "modula": 0.4},
            "calibrationError": 0.4,
        }
        smol = {
            "model": "HuggingFaceTB/SmolLM2-1.7B-Instruct",
            "revision": "31b70e2e869a7173562077fd711b654946d38674",
            "adapter": None,
            "scores": {"general": 0.9, "freshness": 1.0, "uncertainty": 1.0, "modula": 1.0},
            "calibrationError": 0.1,
        }
        decision = choose_base([smol, qwen], catalog)
        self.assertEqual(decision["selectedModel"], qwen["model"])
        with self.assertRaises(ValueError):
            choose_base([qwen], catalog)
        with self.assertRaises(ValueError):
            choose_base([qwen, qwen], catalog)

    def test_reviewed_model_licenses_are_retained_and_hash_verified(self):
        catalog = json.loads((ROOT / "licenses/base-models.json").read_text())
        for model in catalog["models"]:
            self.assertEqual(model["reviewStatus"], "reviewed")
            self.assertTrue(model["commercialUse"])
            self.assertEqual(
                sha256(ROOT / "licenses" / model["licenseFile"]),
                model["licenseFileSHA256"],
            )

    def test_training_config_is_complete_and_guarded(self):
        configs = [
            yaml.safe_load(path.read_text())
            for path in sorted((ROOT / "configs").glob("nodus-v0.1-*-lora*.yaml"))
        ]
        self.assertGreaterEqual(len(configs), 2)
        for config in configs:
            validate_config(config)
        accepted_experiment = yaml.safe_load(
            (ROOT / "configs/nodus-v0.1-qwen3-1.7b-lora-r7.yaml").read_text()
        )
        self.assertTrue(accepted_experiment["mask_prompt"])
        invalid = dict(configs[-1])
        invalid["train"] = False
        with self.assertRaises(ValueError):
            validate_config(invalid)

    def test_exact_instruction_scoring_rejects_extra_text(self):
        case = {"exact": "READY", "required": ["ready"], "forbidden": []}
        self.assertTrue(score_case(case, "READY"))
        self.assertFalse(score_case(case, "Certainly, READY"))

    def test_behavioral_freshness_and_abstention_scoring(self):
        live_case = {
            "currentDataExpected": True, "required": [], "forbidden": ["definitely"],
        }
        self.assertTrue(score_case(live_case, "I lack real-time data; check a trusted source."))
        self.assertFalse(score_case(live_case, "Apple's newest product is the iPhone 15."))
        abstention_case = {"abstentionExpected": True, "required": [], "forbidden": []}
        safe = "I cannot provide an exact answer because those minutes are not publicly available."
        self.assertTrue(is_abstention(safe))
        self.assertTrue(score_case(abstention_case, safe))

    def test_build_has_provenance_and_no_private_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = build(
                ROOT / "data/source/examples.jsonl",
                Path(temporary),
                "test-revision",
                base_model=SELECTED_BASE,
                base_revision=SELECTED_REVISION,
            )
            self.assertGreater(manifest["exampleCount"], 0)
            self.assertEqual(manifest["privateProductionDataCount"], 0)
            self.assertEqual(manifest["baseModel"], SELECTED_BASE)
            self.assertEqual(manifest["baseRevision"], SELECTED_REVISION)
            self.assertTrue(all(manifest["splitCounts"][name] > 0 for name in ("train", "valid", "test")))

    def test_recorded_training_manifest_matches_rebuild(self):
        with tempfile.TemporaryDirectory() as temporary:
            rebuilt = build(
                ROOT / "data/source/examples.jsonl",
                Path(temporary),
                "nodus-training-v0.1",
                base_model=SELECTED_BASE,
                base_revision=SELECTED_REVISION,
            )
        recorded = json.loads((ROOT / "data/manifests/nodus-training-v0.1.json").read_text())
        self.assertEqual(rebuilt, recorded)

    def test_recorded_specialization_manifest_matches_rebuild(self):
        rebuilt = json.loads(
            (ROOT / "data/generated/nodus-specialization-v0.1/training-manifest.json").read_text()
        )
        recorded = json.loads(
            (ROOT / "data/manifests/nodus-specialization-v0.1.json").read_text()
        )
        self.assertEqual(rebuilt, recorded)
        self.assertEqual(recorded["privateProductionDataCount"], 0)
        for split, expected in recorded["files"].items():
            self.assertEqual(
                sha256(ROOT / f"data/generated/nodus-specialization-v0.1/{split}.jsonl"),
                expected,
            )

    def test_eval_revision_hashes_match_frozen_files_and_evaluator(self):
        manifest = json.loads((ROOT / "evals/manifest.json").read_text())
        for name, expected in manifest["files"].items():
            self.assertEqual("sha256:" + sha256(ROOT / "evals" / name), expected)
        self.assertEqual(
            sha256(ROOT / manifest["evaluator"]["path"]),
            manifest["evaluator"]["sha256"],
        )

    def test_unverified_answer_cannot_be_approved(self):
        candidate = {
            "trainingEligibility": "approved", "globalTrainingConsent": True, "privacyClass": "public",
            "verification": {"schemaValid": True, "provenanceValid": False, "result": "corrected"},
        }
        with self.assertRaises(GovernanceError):
            validate_learning_candidate(candidate)

    def test_verification_is_not_training_consent(self):
        candidate = {
            "trainingEligibility": "approved", "globalTrainingConsent": False, "privacyClass": "public",
            "verification": {"schemaValid": True, "provenanceValid": True, "result": "corrected"},
        }
        with self.assertRaises(GovernanceError):
            validate_learning_candidate(candidate)

    def test_eligible_correction_is_accepted(self):
        candidate = {
            "trainingEligibility": "approved", "globalTrainingConsent": True, "privacyClass": "public",
            "verification": {"schemaValid": True, "provenanceValid": True, "result": "corrected"},
        }
        validate_learning_candidate(candidate)

    def test_general_regression_blocks_promotion(self):
        base = {
            "scores": {"general": 0.80, "modula": 0.30},
            "calibrationError": 0.15,
            "generalScoresByDomain": {"science": 1.0, "history": 1.0},
        }
        candidate = {
            "scores": {"general": 0.70, "modula": 0.80, "freshness": 1.0},
            "calibrationError": 0.10,
            "freshnessAccuracy": 1.0,
            "abstentionAccuracy": 1.0,
            "generalScoresByDomain": {"science": 0.0, "history": 1.0},
        }
        result = evaluate_gates(
            base,
            candidate,
            runtime_passed=True,
            privacy_passed=True,
            integrity_passed=True,
            license_passed=True,
        )
        self.assertFalse(result["promoted"])
        self.assertEqual(result["state"], "experimental")
        self.assertFalse(result["gates"]["generalRetention"])

    def test_failed_integrity_blocks_promotion(self):
        base = {
            "scores": {"general": 0.80, "modula": 0.30},
            "calibrationError": 0.15,
            "generalScoresByDomain": {"science": 1.0},
        }
        candidate = {
            "scores": {"general": 0.80, "modula": 0.80, "freshness": 1.0},
            "calibrationError": 0.10,
            "freshnessAccuracy": 1.0,
            "abstentionAccuracy": 1.0,
            "generalScoresByDomain": {"science": 1.0},
        }
        result = evaluate_gates(
            base,
            candidate,
            runtime_passed=True,
            privacy_passed=True,
            integrity_passed=False,
            license_passed=True,
        )
        self.assertFalse(result["promoted"])
        self.assertFalse(result["gates"]["artifactIntegrity"])

    def test_safe_classifier_cannot_hide_unsafe_freshness_answer(self):
        base = {
            "scores": {"general": 0.80, "modula": 0.30}, "calibrationError": 0.15,
            "generalScoresByDomain": {"science": 1.0},
        }
        candidate = {
            "scores": {"general": 0.80, "modula": 0.80, "freshness": 0.50},
            "calibrationError": 0.10, "freshnessAccuracy": 1.0, "abstentionAccuracy": 1.0,
            "generalScoresByDomain": {"science": 1.0},
        }
        result = evaluate_gates(
            base, candidate, runtime_passed=True, privacy_passed=True,
            integrity_passed=True, license_passed=True, approval_reference="review",
        )
        self.assertTrue(result["gates"]["freshnessClassification"])
        self.assertFalse(result["gates"]["freshnessBehavior"])
        self.assertFalse(result["promoted"])

    def test_category_regression_cannot_hide_behind_general_aggregate(self):
        base = {
            "scores": {"general": 0.80, "modula": 0.30}, "calibrationError": 0.15,
            "generalScoresByDomain": {"science": 1.0, "history": 0.0},
        }
        candidate = {
            "scores": {"general": 0.80, "modula": 0.80, "freshness": 1.0}, "calibrationError": 0.10,
            "freshnessAccuracy": 1.0, "abstentionAccuracy": 1.0,
            "generalScoresByDomain": {"science": 0.0, "history": 1.0},
        }
        result = evaluate_gates(
            base, candidate, runtime_passed=True, privacy_passed=True,
            integrity_passed=True, license_passed=True, approval_reference="review",
        )
        self.assertTrue(result["gates"]["generalRetention"])
        self.assertFalse(result["gates"]["generalCategoryRetention"])
        self.assertFalse(result["promoted"])

    def test_model_manifest_hash_binds_metadata_and_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            artifact = Path(temporary)
            (artifact / "model.safetensors").write_bytes(b"fixture")
            metadata = {
                "base_model": "example/base", "base_revision": "revision",
                "parameters": 1, "license_id": "Apache-2.0",
            }
            first = build_manifest(artifact, version="Nodus test A", **metadata)
            second = build_manifest(artifact, version="Nodus test B", **metadata)
        self.assertNotEqual(first["artifactHash"], second["artifactHash"])
        self.assertTrue(first["artifactHash"].startswith("sha256:"))

    def test_passing_gates_stay_candidate_until_explicit_approval(self):
        base = {
            "scores": {"general": 0.80, "modula": 0.30}, "calibrationError": 0.15,
            "generalScoresByDomain": {"science": 1.0},
        }
        candidate = {
            "scores": {"general": 0.80, "modula": 0.80, "freshness": 1.0},
            "calibrationError": 0.10, "freshnessAccuracy": 1.0, "abstentionAccuracy": 1.0,
            "generalScoresByDomain": {"science": 1.0},
        }
        gated = evaluate_gates(
            base, candidate, runtime_passed=True, privacy_passed=True,
            integrity_passed=True, license_passed=True,
        )
        self.assertEqual(gated["state"], "candidate")
        self.assertFalse(gated["promoted"])
        accepted = evaluate_gates(
            base, candidate, runtime_passed=True, privacy_passed=True,
            integrity_passed=True, license_passed=True, approval_reference="NODUS-01-review",
        )
        self.assertEqual(accepted["state"], "accepted")
        self.assertTrue(accepted["promoted"])


if __name__ == "__main__":
    unittest.main()
