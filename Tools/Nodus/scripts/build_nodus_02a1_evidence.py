from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


MODEL_HASH = "55c62c3b63fc932dc3d1140dbe0ad4254cc1398c76a59c044a42e20d9c956ad8"
RATINGS = {"good", "wrong", "unsure", "outdated", "hallucinated"}
FAILURES = {
    "identity_hallucination",
    "general_knowledge_error",
    "modula_knowledge_error",
    "authority_error",
    "freshness_failure",
    "search_grounding_failure",
    "knowledge_grounding_failure",
    "memory_misuse",
    "unsupported_capability",
    "false_premise_failure",
    "hallucination",
    "instruction_following",
    "reasoning_error",
    "context_failure",
    "over_abstention",
    "under_abstention",
}
ROOT_CAUSES = {
    "MODEL",
    "RETRIEVAL",
    "ROUTING",
    "PROMPT / CONTEXT",
    "SEARCH PROVIDER",
    "MEMORY",
    "KNOWLEDGE",
    "UI / ORCHESTRATION",
    "UNKNOWN",
}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text())


def review_map(payload: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(payload, list):
        raise ValueError("reviews must be a JSON array")
    result: dict[str, dict[str, Any]] = {}
    for item in payload:
        if not isinstance(item, dict) or not isinstance(item.get("messageID"), str):
            raise ValueError("every review needs a string messageID")
        if item["messageID"] in result:
            raise ValueError(f"duplicate review: {item['messageID']}")
        rating = item.get("developerRating")
        if rating not in RATINGS:
            raise ValueError(f"invalid or missing rating for {item['messageID']}")
        correction = item.get("correction")
        if rating in {"wrong", "outdated", "hallucinated"} and not str(correction or "").strip():
            raise ValueError(f"correction required for {item['messageID']}")
        failures = item.get("failureTaxonomy", [])
        if not isinstance(failures, list) or any(value not in FAILURES for value in failures):
            raise ValueError(f"invalid failure taxonomy for {item['messageID']}")
        root_cause = item.get("rootCause")
        if failures and root_cause not in ROOT_CAUSES:
            raise ValueError(f"root cause required for failed record {item['messageID']}")
        if not failures and root_cause is not None and root_cause not in ROOT_CAUSES:
            raise ValueError(f"invalid root cause for {item['messageID']}")
        result[item["messageID"]] = item
    return result


def evaluation_map(payload: Any) -> dict[str, dict[str, Any]]:
    if payload is None:
        return {}
    if not isinstance(payload, list):
        raise ValueError("developer evaluations must be a JSON array")
    return {item["id"]: item for item in payload if isinstance(item, dict) and isinstance(item.get("id"), str)}


def build_records(
    conversations_payload: Any,
    evaluations_payload: Any,
    reviews_payload: Any,
) -> list[dict[str, Any]]:
    conversations = conversations_payload.get("conversations") if isinstance(conversations_payload, dict) else None
    if not isinstance(conversations, list):
        raise ValueError("conversation export must contain a conversations array")
    reviews = review_map(reviews_payload)
    evaluations = evaluation_map(evaluations_payload)
    records: list[dict[str, Any]] = []
    seen_reviews: set[str] = set()

    for conversation in conversations:
        if not isinstance(conversation, dict):
            continue
        previous_user: dict[str, Any] | None = None
        for message in conversation.get("messages", []):
            if not isinstance(message, dict):
                continue
            if message.get("role") == "user":
                previous_user = message
                continue
            if message.get("role") != "nodus" or previous_user is None:
                continue
            message_id = message.get("id")
            if message_id not in reviews:
                continue
            seen_reviews.add(message_id)
            review = reviews[message_id]
            evaluation = evaluations.get(message_id, {})
            details = message.get("details") or {}
            answer = message.get("answer") or {}
            confidence = answer.get("confidence") or {}
            citations = message.get("citations") or []
            web_sources = [
                {
                    "title": source.get("title"),
                    "domain": source.get("sourceName"),
                    "url": source.get("url"),
                    "retrievedAt": source.get("retrievedAt"),
                }
                for source in citations
                if source.get("kind") == "web"
            ]
            knowledge_sources = [
                {
                    "title": source.get("title"),
                    "sourceName": source.get("sourceName"),
                    "collectionName": source.get("collectionName"),
                    "location": source.get("location"),
                }
                for source in citations
                if source.get("kind") == "knowledge"
            ]
            record = {
                "schemaVersion": 1,
                "conversationID": conversation.get("id"),
                "messageID": message_id,
                "prompt": previous_user.get("text"),
                "response": message.get("text"),
                "model": answer.get("modelVersion") or "Nodus R7 Experimental",
                "modelHash": MODEL_HASH,
                "thinkEnabled": details.get("reasoningMode") == "deep",
                "searchEnabled": bool(details.get("searchEnabled", False)),
                "knowledgeCollections": sorted(conversation.get("attachedKnowledgeCollectionIDs", [])),
                "knowledgeChunksUsed": details.get("knowledgeChunkCount", 0),
                "knowledgeSources": knowledge_sources,
                "memoryItemCount": len(details.get("memoryItemIDs", [])),
                "searchSources": web_sources,
                "freshnessResult": answer.get("freshness"),
                "confidenceResult": confidence.get("band"),
                "latency": {
                    "generationSeconds": details.get("generationDuration"),
                    "retrievalSeconds": details.get("retrievalDuration"),
                    "searchSeconds": details.get("searchDuration"),
                    "modelSeconds": answer.get("latencySeconds"),
                    "tokensPerSecond": answer.get("tokensPerSecond"),
                    "inferencePasses": details.get("inferencePasses"),
                },
                "developerRating": review["developerRating"],
                "correction": review.get("correction") or evaluation.get("note"),
                "failureTaxonomy": review.get("failureTaxonomy", []),
                "rootCause": review.get("rootCause"),
                "reviewNote": review.get("reviewNote"),
                "createdAt": message.get("createdAt"),
            }
            records.append(record)

    missing = sorted(set(reviews) - seen_reviews)
    if missing:
        raise ValueError(f"reviews reference unknown Nodus message IDs: {missing}")
    records.sort(key=lambda item: (item.get("createdAt") or "", item["messageID"]))
    return records


def write_jsonl(records: list[dict[str, Any]], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    lines = [json.dumps(record, sort_keys=True, separators=(",", ":")) for record in records]
    output.write_text("".join(f"{line}\n" for line in lines))


def main() -> None:
    parser = argparse.ArgumentParser(description="Build reviewed NODUS-02A.1 evidence JSONL")
    parser.add_argument("--conversations", type=Path, required=True)
    parser.add_argument("--evaluations", type=Path)
    parser.add_argument("--reviews", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    evaluations = load_json(args.evaluations) if args.evaluations else []
    records = build_records(load_json(args.conversations), evaluations, load_json(args.reviews))
    write_jsonl(records, args.output)
    print(f"wrote {len(records)} reviewed NODUS-02A.1 records to {args.output}")


if __name__ == "__main__":
    main()
