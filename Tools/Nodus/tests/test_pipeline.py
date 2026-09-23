import json
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path

import yaml
from mlx_lm.tuner.datasets import ChatDataset

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from build_dataset import build
from build_corpus_01b import ALL_CATEGORIES, PROFILE_COUNTS, record
from fit_calibration import fit as fit_calibration
from build_model_manifest import build_manifest
from build_specialization_dataset import build as build_specialization
from common import GovernanceError, sha256, validate_learning_candidate
from evaluate import is_abstention, score_case
from promotion_gate import evaluate_gates
from select_base import choose_base
from train import validate_config
from task_contract import (
    SYSTEM_PROMPT,
    TaskMode,
    classification_label,
    messages_for,
    normalize_generated_output,
    task_prompt,
)
from evaluate_v2 import score_case as score_case_v2
from calibrate_v2 import calibrate as calibrate_v2
from promotion_gate_v2 import evaluate_gates as evaluate_gates_v2
from select_checkpoint_v2 import select as select_checkpoint_v2
from build_r7_dataset import DEFAULT_QUOTAS, task_enhanced_sample

SELECTED_BASE = "Qwen/Qwen3-1.7B"
SELECTED_REVISION = "70d244cc86ccca08cf5af4e1e306ecf908b1ad5e"


class DatasetPipelineTests(unittest.TestCase):
    def test_mlx_chat_dataset_masks_system_and_user_tokens(self):
        class FixtureTokenizer:
            @staticmethod
            def apply_chat_template(messages, add_generation_prompt=False, **_):
                rendered = "".join(
                    f"<|{message['role']}|>{message['content']}<|im_end|>"
                    for message in messages
                )
                if add_generation_prompt:
                    rendered += "<|assistant|>"
                return list(rendered.encode("utf-8"))

        messages = messages_for(TaskMode.CLASSIFY_FRESHNESS, "Who wrote Hamlet?", "stable")
        dataset = ChatDataset(
            [{"messages": messages}],
            FixtureTokenizer(),
            mask_prompt=True,
        )
        tokens, supervised_offset = dataset.process(dataset[0])
        supervised_text = bytes(tokens[supervised_offset:]).decode("utf-8")
        self.assertGreater(supervised_offset, 0)
        self.assertEqual(supervised_text, "stable<|im_end|>")
        self.assertNotIn("Who wrote Hamlet?", supervised_text)
        self.assertNotIn(SYSTEM_PROMPT, supervised_text)

    def test_task_modes_use_one_system_prompt_and_narrow_contracts(self):
        for mode in TaskMode:
            messages = messages_for(mode, "fixture", "result")
            self.assertEqual(messages[0], {"role": "system", "content": SYSTEM_PROMPT})
            self.assertTrue(messages[1]["content"].startswith(f"TASK: {mode.value}"))
            self.assertEqual(messages[-1]["role"], "assistant")
        self.assertIn("current_data_required", task_prompt(TaskMode.CLASSIFY_FRESHNESS, "today?"))

    def test_reasoning_wrappers_never_enter_task_output_contract(self):
        wrapped = "<think>not part of the contract</think>\ncurrent_data_required<|im_end|>"
        self.assertEqual(normalize_generated_output(wrapped), "current_data_required")
        self.assertEqual(classification_label(wrapped), "current_data_required")

    def test_v2_scoring_separates_labels_schema_and_prose(self):
        label = {
            "taskMode": "CLASSIFY_FRESHNESS", "expected": "stable", "forbidden": [],
        }
        self.assertEqual(score_case_v2(label, "stable"), (True, "correct"))
        self.assertEqual(score_case_v2(label, "Stable, because it is old."), (False, "wrong_label"))
        structured = {
            "taskMode": "STRUCTURED_ACTION",
            "expectedSubset": {"type": "record.create", "proposalOnly": True},
            "forbidden": [],
        }
        self.assertEqual(
            score_case_v2(structured, '{"type":"record.create","proposalOnly":true,"fields":{}}'),
            (True, "correct"),
        )
        prose = {
            "taskMode": "GENERAL_ANSWER", "requiredAnyGroups": [["scatter", "rayleigh"]],
            "forbidden": [],
        }
        self.assertEqual(score_case_v2(prose, "Rayleigh scattering makes the sky appear blue."), (True, "correct"))

    def test_v2_calibration_is_external_and_task_separated(self):
        report = {
            "model": SELECTED_BASE,
            "revision": SELECTED_REVISION,
            "adapter": "fixture",
            "results": [
                {"suite": "general-v2", "id": f"g-{index}", "passed": passed}
                for index, passed in enumerate((True, True, False, True))
            ] + [
                {"suite": "abstention-v2", "id": f"a-{index}", "passed": passed}
                for index, passed in enumerate((True, False, True, False))
            ],
        }
        result = calibrate_v2(report)
        self.assertEqual(set(result["buckets"]), {"general factual", "abstention"})
        self.assertGreaterEqual(result["calibrationError"], 0.0)
        self.assertLessEqual(result["calibrationError"], 1.0)

    def test_v2_promotion_gate_is_fail_closed_across_every_required_metric(self):
        base = {"scores": {"general-v2": 0.8, "modula-v2": 0.2, "hallucination-v2": 0.8}}
        candidate = {
            "scores": {"general-v2": 0.76, "modula-v2": 0.4, "hallucination-v2": 0.76},
            "freshnessAccuracy": 0.9,
            "abstentionAccuracy": 0.85,
            "falseAbstentionRate": 0.1,
            "verificationAccuracy": 0.9,
            "structuredSchemaValidity": 0.95,
            "unsupportedCapabilityRejection": 1.0,
            "authorityAccuracy": 0.95,
        }
        passing = evaluate_gates_v2(base, candidate, {"calibrationError": 0.3})
        self.assertEqual(passing["state"], "candidate")
        self.assertFalse(passing["promoted"])
        candidate["abstentionAccuracy"] = 0.84
        failing = evaluate_gates_v2(base, candidate, {"calibrationError": 0.3})
        self.assertEqual(failing["state"], "experimental")
        self.assertFalse(failing["gates"]["abstention"])

    def test_v2_checkpoint_selection_uses_task_metrics_not_loss_alone(self):
        weak = {
            "scores": {
                "general-v2": 0.9, "modula-v2": 0.1, "freshness-v2": 0.2,
                "abstention-v2": 0.2, "verification-v2": 0.2,
                "structured-action-v2": 0.1,
            },
            "falseAbstentionRate": 0.5,
        }
        balanced = {
            "scores": {
                "general-v2": 0.86, "modula-v2": 0.5, "freshness-v2": 0.9,
                "abstention-v2": 0.9, "verification-v2": 0.9,
                "structured-action-v2": 0.8,
            },
            "falseAbstentionRate": 0.05,
        }
        result = select_checkpoint_v2([
            {"step": 100, "validationLoss": 0.1, "report": weak},
            {"step": 200, "validationLoss": 0.2, "report": balanced},
        ])
        self.assertEqual(result["selectedStep"], 200)
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

    def test_nodus_01c_configs_pin_alignment_controls(self):
        configs = sorted((ROOT / "configs").glob("nodus-01c-*.yaml"))
        self.assertEqual(len(configs), 5)
        for path in configs:
            config = yaml.safe_load(path.read_text())
            validate_config(config)
            self.assertEqual(config["model"], SELECTED_BASE)
            self.assertEqual(config["revision"], SELECTED_REVISION)
            self.assertTrue(config["mask_prompt"])
            self.assertLessEqual(float(config["learning_rate"]), 0.00002)

    def test_r7_sampling_is_deterministic_and_matches_declared_task_weights(self):
        records = [
            {
                "messages": [{"role": "assistant", "content": mode}],
                "metadata": {"taskMode": mode, "id": mode},
            }
            for mode in DEFAULT_QUOTAS
        ]
        quotas = {mode: 2 for mode in DEFAULT_QUOTAS}
        first = task_enhanced_sample(records, quotas, seed=71)
        second = task_enhanced_sample(records, quotas, seed=71)
        self.assertEqual(first, second)
        counts = Counter(item["metadata"]["taskMode"] for item in first)
        self.assertEqual(counts, Counter(quotas))

    def test_nodus_01b_profiles_are_controlled_six_thousand_example_mixtures(self):
        self.assertEqual(set(PROFILE_COUNTS), {"r3", "r4", "r5"})
        for profile, counts in PROFILE_COUNTS.items():
            self.assertEqual(set(counts), set(ALL_CATEGORIES), profile)
            self.assertEqual(sum(counts.values()), 6_000, profile)
        self.assertGreater(PROFILE_COUNTS["r4"]["MODULA_ARCHITECTURE"], PROFILE_COUNTS["r3"]["MODULA_ARCHITECTURE"])
        self.assertGreater(PROFILE_COUNTS["r5"]["FRESHNESS"], PROFILE_COUNTS["r3"]["FRESHNESS"])

    def test_nodus_01b_manifests_record_provenance_deduplication_and_no_leakage(self):
        for profile in ("r3", "r4", "r5"):
            manifest = json.loads((ROOT / f"data/manifests/nodus-01b-{profile}.json").read_text())
            self.assertEqual(manifest["exampleCount"], 6_000)
            self.assertTrue(manifest["provenanceComplete"])
            self.assertEqual(manifest["privateProductionDataCount"], 0)
            self.assertEqual(manifest["splitLeakage"], "PASS")
            self.assertEqual(manifest["splitPolicy"], "semantic-group-hash-80-10-10")
            self.assertGreater(manifest["duplicateRemoval"]["exact"], 0)
            self.assertGreater(manifest["duplicateRemoval"]["near"], 0)
            self.assertTrue(all(manifest["splitCounts"][name] > 0 for name in ("train", "valid", "test")))

    def test_nodus_01b_configs_pin_base_dataset_and_experiment_controls(self):
        for profile in ("r3", "r4", "r5"):
            config = yaml.safe_load((ROOT / f"configs/nodus-01b-{profile}.yaml").read_text())
            validate_config(config)
            self.assertEqual(config["model"], SELECTED_BASE)
            self.assertEqual(config["revision"], SELECTED_REVISION)
            self.assertEqual(config["dataset_revision"], f"nodus-01b-{profile}-v1")
            self.assertTrue(config["mask_prompt"])

    def test_generation_provenance_hash_is_deterministic(self):
        first = record(
            item_id="fixture", group="fixture-group", category="NODUS", prompt="What is Nodus?",
            response="A local model.", source="modula-nodus01b-spec", concept="identity",
            document="fixture", seed=17,
        )
        second = record(
            item_id="fixture", group="fixture-group", category="NODUS", prompt="What is Nodus?",
            response="A local model.", source="modula-nodus01b-spec", concept="identity",
            document="fixture", seed=17,
        )
        self.assertEqual(first["generationHash"], second["generationHash"])

    def test_bucket_calibration_uses_validation_accuracy_with_smoothing(self):
        report = {
            "model": SELECTED_BASE, "revision": SELECTED_REVISION, "adapter": "fixture",
            "results": [
                {"confidenceBucket": "stable_answer", "passed": True},
                {"confidenceBucket": "stable_answer", "passed": True},
                {"confidenceBucket": "uncertain", "passed": False},
            ],
        }
        calibration = fit_calibration(report)
        self.assertEqual(calibration["method"], "deterministic-bucket-beta-calibration")
        self.assertGreater(calibration["buckets"]["stable_answer"], calibration["buckets"]["uncertain"])

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
        with tempfile.TemporaryDirectory() as temporary:
            generated = Path(temporary)
            parent = generated / "nodus-training-v0.1"
            specialization = generated / "nodus-specialization-v0.1"
            build(
                ROOT / "data/source/examples.jsonl",
                parent,
                "nodus-training-v0.1",
                base_model=SELECTED_BASE,
                base_revision=SELECTED_REVISION,
            )
            rebuilt = build_specialization(
                parent,
                specialization,
                "nodus-specialization-v0.1",
            )
            rebuilt_files = {
                split: sha256(specialization / f"{split}.jsonl")
                for split in ("train", "valid", "test")
            }
        recorded = json.loads(
            (ROOT / "data/manifests/nodus-specialization-v0.1.json").read_text()
        )
        self.assertEqual(rebuilt, recorded)
        self.assertEqual(recorded["privateProductionDataCount"], 0)
        for split, expected in recorded["files"].items():
            self.assertEqual(rebuilt_files[split], expected)

    def test_eval_revision_hashes_match_frozen_files_and_evaluator(self):
        manifest = json.loads((ROOT / "evals/manifest.json").read_text())
        for name, expected in manifest["files"].items():
            self.assertEqual("sha256:" + sha256(ROOT / "evals" / name), expected)
        self.assertEqual(
            sha256(ROOT / manifest["evaluator"]["path"]),
            manifest["evaluator"]["sha256"],
        )

    def test_eval_v2_manifest_binds_suites_evaluator_and_task_contract(self):
        manifest = json.loads((ROOT / "evals/manifest-v2.json").read_text())
        self.assertEqual(manifest["caseCount"], 382)
        for name, expected in manifest["files"].items():
            self.assertEqual("sha256:" + sha256(ROOT / "evals" / name), expected)
        self.assertEqual(
            "sha256:" + sha256(ROOT / manifest["evaluator"]),
            manifest["evaluatorSHA256"],
        )
        self.assertEqual(
            "sha256:" + sha256(ROOT / manifest["taskContract"]),
            manifest["taskContractSHA256"],
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

    def test_nodus_01b_requires_absolute_modula_gain_and_calibration_ceiling(self):
        base = {
            "scores": {"general": 1.0, "modula": 0.40, "freshness": 1.0},
            "calibrationError": 0.4311,
            "freshnessAccuracy": 1.0,
            "abstentionAccuracy": 1.0,
            "generalScoresByDomain": {"science": 1.0},
        }
        candidate = {
            "scores": {"general": 1.0, "modula": 0.54, "freshness": 1.0},
            "calibrationError": 0.4400,
            "freshnessAccuracy": 1.0,
            "abstentionAccuracy": 1.0,
            "generalScoresByDomain": {"science": 1.0},
        }
        result = evaluate_gates(
            base, candidate, runtime_passed=True, privacy_passed=True,
            integrity_passed=True, license_passed=True, approval_reference="review",
        )
        self.assertFalse(result["gates"]["modulaImprovement"])
        self.assertFalse(result["gates"]["confidenceCalibration"])
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
