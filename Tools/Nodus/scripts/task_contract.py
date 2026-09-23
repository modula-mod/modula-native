from __future__ import annotations

import json
import re
from enum import StrEnum
from typing import Any


SYSTEM_PROMPT = (
    "You are Nodus, Modula's concise general-purpose offline assistant. "
    "Never claim live information without current evidence. Actions are proposals only."
)


class TaskMode(StrEnum):
    GENERAL_ANSWER = "GENERAL_ANSWER"
    MODULA_ANSWER = "MODULA_ANSWER"
    SUMMARIZE = "SUMMARIZE"
    REWRITE = "REWRITE"
    CLASSIFY = "CLASSIFY"
    EXTRACT = "EXTRACT"
    CLASSIFY_FRESHNESS = "CLASSIFY_FRESHNESS"
    SHOULD_ABSTAIN = "SHOULD_ABSTAIN"
    VERIFY_RECOMMENDATION = "VERIFY_RECOMMENDATION"
    CLASSIFY_INTENT = "CLASSIFY_INTENT"
    STRUCTURED_ACTION = "STRUCTURED_ACTION"


OUTPUT_CONTRACTS = {
    TaskMode.GENERAL_ANSWER: "Answer directly in concise prose.",
    TaskMode.MODULA_ANSWER: "Answer from accepted Modula architecture. Do not invent capabilities.",
    TaskMode.SUMMARIZE: "Return only an accurate concise summary.",
    TaskMode.REWRITE: "Return only the rewritten text while preserving meaning.",
    TaskMode.CLASSIFY: "Return only the requested classification label.",
    TaskMode.EXTRACT: "Return only the requested facts.",
    TaskMode.CLASSIFY_FRESHNESS: (
        "Return exactly one label: stable | possibly_stale | current_data_required | unknown."
    ),
    TaskMode.SHOULD_ABSTAIN: (
        "Return exactly one label: answer | answer_with_uncertainty | abstain."
    ),
    TaskMode.VERIFY_RECOMMENDATION: (
        "Return exactly one label: not_needed | recommended | required."
    ),
    TaskMode.CLASSIFY_INTENT: "Return only the supported intent label or unsupported.",
    TaskMode.STRUCTURED_ACTION: (
        "Return one JSON object using the supported Modula intent schema. Return "
        '{"type":"unsupported"} for an unsupported capability. Do not add prose.'
    ),
}


def task_prompt(mode: TaskMode | str, input_text: str) -> str:
    selected = TaskMode(mode)
    return (
        f"TASK: {selected.value}\n\n"
        f"INPUT:\n{input_text.strip()}\n\n"
        f"OUTPUT CONTRACT:\n{OUTPUT_CONTRACTS[selected]}"
    )


def messages_for(mode: TaskMode | str, input_text: str, output: str | None = None) -> list[dict[str, str]]:
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": task_prompt(mode, input_text)},
    ]
    if output is not None:
        messages.append({"role": "assistant", "content": output.strip()})
    return messages


def normalize_generated_output(output: str) -> str:
    """Remove Qwen reasoning/special-token wrappers without exposing reasoning as a contract."""
    text = re.sub(r"<think>.*?</think>", "", output, flags=re.DOTALL | re.IGNORECASE)
    text = text.replace("<|im_end|>", "").replace("<|endoftext|>", "")
    return text.strip()


def classification_label(output: str) -> str:
    text = normalize_generated_output(output).lower().strip()
    if not text:
        return ""
    first = text.splitlines()[0].strip().strip("`* .,:;\"'")
    return re.sub(r"[\s-]+", "_", first)


def json_object(output: str) -> dict[str, Any] | None:
    text = normalize_generated_output(output)
    fenced = re.fullmatch(r"```(?:json)?\s*(.*?)\s*```", text, flags=re.DOTALL | re.IGNORECASE)
    if fenced:
        text = fenced.group(1)
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None
