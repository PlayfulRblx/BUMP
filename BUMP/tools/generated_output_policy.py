from __future__ import annotations

import re
from pathlib import Path


GENERATED_AT_LINE_RE = re.compile(r"(?m)^-- Generated at [^\n]+\n")
GENERATED_JSON_UTC_FIELD_RE = re.compile(
    r'("(?:generatedUtc|GeneratedUtc)"\s*:\s*)"[^"]*"'
)
GENERATED_LUA_UTC_FIELD_RE = re.compile(
    r'(?m)(\b(?:generatedUtc|GeneratedUtc)\s*=\s*)"[^"]*"'
)


def normalize_generated_timestamps(payload: str) -> str:
    payload = GENERATED_AT_LINE_RE.sub("-- Generated at <generated>.\n", payload)
    payload = GENERATED_JSON_UTC_FIELD_RE.sub(r'\1"<generated>"', payload)
    return GENERATED_LUA_UTC_FIELD_RE.sub(r'\1"<generated>"', payload)


def write_generated_text(path: Path, payload: str) -> bool:
    """Write generated text only when non-timestamp content changed."""

    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        existing = path.read_text(encoding="utf-8")
        if normalize_generated_timestamps(existing) == normalize_generated_timestamps(payload):
            return False
    path.write_text(payload, encoding="utf-8")
    return True
