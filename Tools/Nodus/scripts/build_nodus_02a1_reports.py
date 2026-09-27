from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean
from typing import Any, Iterable


REPORT_FILES = {
    "failure": "nodus-02a1-failure-clusters.md",
    "think": "nodus-02a1-think-analysis.md",
    "search": "nodus-02a1-search-analysis.md",
    "knowledge": "nodus-02a1-knowledge-analysis.md",
    "memory": "nodus-02a1-memory-analysis.md",
    "r8": "nodus-02a1-r8-evidence.md",
}


def load_records(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        value = json.loads(line)
        if not isinstance(value, dict):
            raise ValueError(f"record {line_number} is not an object")
        records.append(value)
    return records


def percentage(numerator: int, denominator: int) -> str:
    return "n/a" if denominator == 0 else f"{100 * numerator / denominator:.1f}%"


def average(values: Iterable[Any]) -> str:
    usable = [float(value) for value in values if isinstance(value, (int, float))]
    return "n/a" if not usable else f"{mean(usable):.3f} s"


def count_true(records: list[dict[str, Any]], path: tuple[str, str]) -> int:
    return sum(record.get(path[0], {}).get(path[1]) is True for record in records)


def heading(title: str, records: list[dict[str, Any]]) -> list[str]:
    return [f"# {title}", "", f"Reviewed physical interactions: **{len(records)}**", ""]


def failure_report(records: list[dict[str, Any]]) -> str:
    failures = Counter(label for record in records for label in record.get("failureTaxonomy", []))
    roots = Counter(record.get("rootCause") for record in records if record.get("rootCause"))
    lines = heading("NODUS-02A.1 failure clusters", records)
    if not failures:
        lines += ["No reviewed failure clusters were observed.", ""]
    else:
        for index, (label, count) in enumerate(failures.most_common(), start=1):
            examples = [record for record in records if label in record.get("failureTaxonomy", [])][:3]
            example_roots = Counter(record.get("rootCause") or "UNKNOWN" for record in examples)
            lines += [
                f"## Cluster {index}: {label.replace('_', ' ').title()}", "",
                f"Occurrences: **{count}**. Leading root cause: **{example_roots.most_common(1)[0][0]}**.", "",
            ]
            for record in examples:
                lines.append(f"- `{record.get('physical', {}).get('scenarioID') or record.get('messageID')}` — {record.get('reviewNote') or record.get('correction') or 'Reviewed failure.'}")
            lines.append("")
    lines += ["## Root-cause distribution", ""]
    lines += [f"- {root}: {count}" for root, count in roots.most_common()] or ["- No classified failures."]
    return "\n".join(lines) + "\n"


def think_report(records: list[dict[str, Any]]) -> str:
    think = [record for record in records if record.get("thinkEnabled")]
    comparisons = Counter(record.get("thinkComparison") for record in think if record.get("thinkComparison"))
    improved_categories = Counter(
        record.get("physical", {}).get("category") or "unclassified"
        for record in think if record.get("thinkComparison") == "better"
    )
    lines = heading("NODUS-02A.1 Think analysis", records)
    lines += [
        f"Think interactions: **{len(think)}**", "",
        f"- Better: {comparisons['better']}",
        f"- Same: {comparisons['same']}",
        f"- Worse: {comparisons['worse']}",
        f"- Average generation latency: {average(record.get('latency', {}).get('generationSeconds') for record in think)}",
        f"- Average inference passes: {('n/a' if not think else f'{mean([record.get('latency', {}).get('inferencePasses') or 0 for record in think]):.2f}')}",
        "", "## Best observed task categories", "",
    ]
    lines += [f"- {category}: {count} improved" for category, count in improved_categories.most_common()] or ["- No reviewed improvements."]
    return "\n".join(lines) + "\n"


def search_report(records: list[dict[str, Any]]) -> str:
    searched = [record for record in records if record.get("searchGrounding")]
    retrieval = count_true(searched, ("searchGrounding", "retrievalCorrect"))
    faithful = count_true(searched, ("searchGrounding", "synthesisFaithful"))
    unsupported = count_true(searched, ("searchGrounding", "unsupportedClaimsAdded"))
    citations = count_true(searched, ("searchGrounding", "citationFidelity"))
    lines = heading("NODUS-02A.1 Search analysis", records)
    lines += [
        f"Search-grounded interactions: **{len(searched)}**", "",
        f"- Retrieval success: {retrieval}/{len(searched)} ({percentage(retrieval, len(searched))})",
        f"- Faithful synthesis: {faithful}/{len(searched)} ({percentage(faithful, len(searched))})",
        f"- Citation fidelity: {citations}/{len(searched)} ({percentage(citations, len(searched))})",
        f"- Unsupported claims added: {unsupported}/{len(searched)} ({percentage(unsupported, len(searched))})",
        f"- Average provider latency: {average(record.get('latency', {}).get('searchSeconds') for record in searched)}",
        f"- Average total generation latency: {average(record.get('latency', {}).get('generationSeconds') for record in searched)}",
    ]
    return "\n".join(lines) + "\n"


def knowledge_report(records: list[dict[str, Any]]) -> str:
    grounded = [record for record in records if record.get("knowledgeGrounding")]
    retrieved = count_true(grounded, ("knowledgeGrounding", "retrievedFactCorrect"))
    correct = count_true(grounded, ("knowledgeGrounding", "finalAnswerCorrect"))
    follows = count_true(grounded, ("knowledgeGrounding", "followsEvidence"))
    identity_failures = sum("identity_hallucination" in record.get("failureTaxonomy", []) for record in grounded)
    lines = heading("NODUS-02A.1 Knowledge analysis", records)
    lines += [
        f"Knowledge-grounded interactions: **{len(grounded)}**", "",
        f"- Correct retrieved fact: {retrieved}/{len(grounded)} ({percentage(retrieved, len(grounded))})",
        f"- Correct final answer: {correct}/{len(grounded)} ({percentage(correct, len(grounded))})",
        f"- Final answer followed evidence: {follows}/{len(grounded)} ({percentage(follows, len(grounded))})",
        f"- Retrieval failures: {len(grounded) - retrieved}",
        f"- Synthesis failures after correct retrieval: {sum(record['knowledgeGrounding']['retrievedFactCorrect'] and not record['knowledgeGrounding']['finalAnswerCorrect'] for record in grounded)}",
        f"- Identity hallucinations with Knowledge active: {identity_failures}",
    ]
    return "\n".join(lines) + "\n"


def memory_report(records: list[dict[str, Any]]) -> str:
    memory = [record for record in records if record.get("memoryAssessment")]
    relevant = count_true(memory, ("memoryAssessment", "relevant"))
    leakage = count_true(memory, ("memoryAssessment", "scopeLeakage"))
    useful = count_true(memory, ("memoryAssessment", "personalizationUseful"))
    lines = heading("NODUS-02A.1 Memory analysis", records)
    lines += [
        f"Memory-backed interactions: **{len(memory)}**", "",
        f"- Relevant memories retrieved: {relevant}/{len(memory)} ({percentage(relevant, len(memory))})",
        f"- Irrelevant memories injected: {len(memory) - relevant}",
        f"- Scope leakage: {leakage}",
        f"- Useful personalization: {useful}/{len(memory)} ({percentage(useful, len(memory))})",
    ]
    return "\n".join(lines) + "\n"


def r8_report(records: list[dict[str, Any]]) -> str:
    by_root: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        if record.get("rootCause"):
            by_root[record["rootCause"]].append(record)
    model_failures = by_root.get("MODEL", [])
    architecture_roots = [
        "RETRIEVAL", "ROUTING", "PROMPT / CONTEXT", "SEARCH PROVIDER", "MEMORY",
        "KNOWLEDGE", "UI / ORCHESTRATION", "UNKNOWN",
    ]
    lines = heading("NODUS-02A.1 R8 evidence", records)
    lines += [
        "## What R8 should learn", "",
        "Only recurring failures classified as `MODEL`, especially where correct retrieved evidence reached R7 and the answer still contradicted or ignored it.", "",
    ]
    if model_failures:
        model_labels = Counter(label for record in model_failures for label in record.get("failureTaxonomy", []))
        lines += [f"- {label}: {count}" for label, count in model_labels.most_common()]
    else:
        lines.append("- No reviewed MODEL-rooted failure is yet eligible for R8 training.")
    lines += ["", "## What R8 should not solve", ""]
    for root in architecture_roots:
        values = by_root.get(root, [])
        if values:
            labels = Counter(label for record in values for label in record.get("failureTaxonomy", []))
            summary = ", ".join(f"{label} ({count})" for label, count in labels.most_common()) or "unclustered"
            lines.append(f"- **{root}** — {len(values)} interaction(s): {summary}")
    if not any(by_root.get(root) for root in architecture_roots):
        lines.append("- No non-model failure was classified in the reviewed evidence.")
    lines += [
        "", "## Decision rule", "",
        "Knowledge-fixed identity errors, Search-fixed freshness questions, retrieval misses, routing errors, provider quality, memory scope, prompt construction, and UI orchestration remain architectural work. They must not be converted automatically into an R8 dataset.", "",
        "No training was performed by NODUS-02A.1.",
    ]
    return "\n".join(lines) + "\n"


def build_reports(records: list[dict[str, Any]]) -> dict[str, str]:
    return {
        "failure": failure_report(records),
        "think": think_report(records),
        "search": search_report(records),
        "knowledge": knowledge_report(records),
        "memory": memory_report(records),
        "r8": r8_report(records),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Build reviewed NODUS-02A.1 Markdown reports")
    parser.add_argument("--records", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--minimum-interactions", type=int, default=75)
    args = parser.parse_args()
    records = load_records(args.records)
    if len(records) < args.minimum_interactions:
        raise ValueError(f"need at least {args.minimum_interactions} reviewed interactions; found {len(records)}")
    args.output_directory.mkdir(parents=True, exist_ok=True)
    for key, content in build_reports(records).items():
        (args.output_directory / REPORT_FILES[key]).write_text(content)
    print(f"wrote {len(REPORT_FILES)} NODUS-02A.1 reports from {len(records)} reviewed interactions")


if __name__ == "__main__":
    main()
