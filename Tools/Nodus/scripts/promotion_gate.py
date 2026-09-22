from __future__ import annotations

import argparse
import json
from pathlib import Path


def evaluate_gates(
    base: dict,
    candidate: dict,
    *,
    runtime_passed: bool,
    privacy_passed: bool,
    integrity_passed: bool,
    license_passed: bool,
    approval_reference: str | None = None,
) -> dict:
    """Return a fail-closed promotion decision without mutating any artifact."""
    general_regression = base["scores"]["general"] - candidate["scores"]["general"]
    modula_improvement = candidate["scores"]["modula"] - base["scores"]["modula"]
    base_domains = base.get("generalScoresByDomain", {})
    candidate_domains = candidate.get("generalScoresByDomain", {})
    domain_regressions = {
        domain: round(score - candidate_domains.get(domain, 0.0), 4)
        for domain, score in base_domains.items()
    }
    base_suite_domains = base.get("scoresBySuiteDomain", {})
    candidate_suite_domains = candidate.get("scoresBySuiteDomain", {})
    base_general_v2 = base_suite_domains.get("general-01b", {})
    candidate_general_v2 = candidate_suite_domains.get("general-01b", {})
    expanded_domain_regressions = {
        domain: round(score - candidate_general_v2.get(domain, 0.0), 4)
        for domain, score in base_general_v2.items()
    }
    expanded_general_regression = None
    expanded_modula_improvement = None
    if "general-01b" in base["scores"] and "general-01b" in candidate["scores"]:
        expanded_general_regression = round(
            base["scores"]["general-01b"] - candidate["scores"]["general-01b"], 4
        )
    if "modula-01b" in base["scores"] and "modula-01b" in candidate["scores"]:
        expanded_modula_improvement = round(
            candidate["scores"]["modula-01b"] - base["scores"]["modula-01b"], 4
        )
    base_modula_v2 = base_suite_domains.get("modula-01b", {})
    candidate_modula_v2 = candidate_suite_domains.get("modula-01b", {})

    def retained_or_better(domain: str) -> bool:
        if not base_modula_v2:
            return True
        return candidate_modula_v2.get(domain, 0.0) >= base_modula_v2.get(domain, 0.0)

    gates = {
        "generalRetention": general_regression <= 0.05,
        "generalCategoryRetention": all(regression <= 0.05 for regression in domain_regressions.values()),
        "expandedGeneralRetention": (
            expanded_general_regression is None or expanded_general_regression <= 0.05
        ),
        "expandedGeneralCategoryRetention": all(
            regression <= 0.05 for regression in expanded_domain_regressions.values()
        ),
        "modulaImprovement": modula_improvement >= 0.15,
        "expandedModulaImprovement": (
            expanded_modula_improvement is None or expanded_modula_improvement >= 0.15
        ),
        "confidenceCalibration": candidate["calibrationError"] < 0.4400,
        "freshnessClassification": candidate["freshnessAccuracy"] >= 0.9,
        "freshnessBehavior": candidate["scores"].get("freshness", 0.0) >= 0.9,
        "abstentionBehavior": candidate.get("abstentionAccuracy", 0.0) >= 0.9,
        "hallucinationResistance": retained_or_better("Hallucination Resistance"),
        "unknownCapability": retained_or_better("Unknown Capability"),
        "falsePremise": retained_or_better("False Premise"),
        "privacy": privacy_passed,
        "runtime": runtime_passed,
        "artifactIntegrity": integrity_passed,
        "licenseValidation": license_passed,
    }
    passed = all(gates.values())
    accepted = passed and bool(approval_reference and approval_reference.strip())
    return {
        "state": "accepted" if accepted else ("candidate" if passed else "experimental"),
        "promoted": accepted,
        "approvalReference": approval_reference if accepted else None,
        "generalRegression": general_regression,
        "modulaImprovement": round(modula_improvement, 4),
        "expandedGeneralRegression": expanded_general_regression,
        "expandedModulaImprovement": expanded_modula_improvement,
        "domainRegressions": domain_regressions,
        "expandedDomainRegressions": expanded_domain_regressions,
        "calibrationPreferredTargetMet": candidate["calibrationError"] <= 0.374,
        "gates": gates,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--runtime-passed", action="store_true")
    parser.add_argument("--privacy-passed", action="store_true")
    parser.add_argument("--integrity-passed", action="store_true")
    parser.add_argument("--license-passed", action="store_true")
    parser.add_argument("--approval-reference", help="Auditable approval reference required for accepted state")
    args = parser.parse_args()
    base = json.loads(args.base.read_text())
    candidate = json.loads(args.candidate.read_text())
    result = evaluate_gates(
        base,
        candidate,
        runtime_passed=args.runtime_passed,
        privacy_passed=args.privacy_passed,
        integrity_passed=args.integrity_passed,
        license_passed=args.license_passed,
        approval_reference=args.approval_reference,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    raise SystemExit(0 if result["promoted"] else 2)


if __name__ == "__main__":
    main()
