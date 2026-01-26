"""Utilities for working with markdown anchor sections."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Iterable, Optional


def _anchor_pair(anchor_name: str) -> tuple[str, str]:
    anchor_name = anchor_name.strip().upper()
    start = f"<!-- {anchor_name}_START -->"
    end = f"<!-- {anchor_name}_END -->"
    return start, end


def extract_between_anchors(content: str, anchor_name: str, *, raise_on_missing: bool = False) -> Optional[str]:
    start, end = _anchor_pair(anchor_name)
    pattern = f"{re.escape(start)}(.*?){re.escape(end)}"
    match = re.search(pattern, content, re.DOTALL)
    if not match:
        if raise_on_missing:
            raise ValueError(f"Anchors for {anchor_name!r} not found")
        return None
    return match.group(1).strip()


def replace_anchor_content(content: str, anchor_name: str, new_content: str) -> str:
    start, end = _anchor_pair(anchor_name)
    new_section = f"{start}\n{new_content}\n{end}"

    pattern = f"{re.escape(start)}.*?{re.escape(end)}"
    if re.search(pattern, content, re.DOTALL):
        return re.sub(pattern, new_section, content, flags=re.DOTALL)

    sep = "\n\n" if not content.endswith("\n") else "\n"
    return f"{content}{sep}{new_section}\n"


def ensure_anchors_exist(content: str, anchor_names: Iterable[str]) -> str:
    for name in anchor_names:
        start, end = _anchor_pair(name)
        if start in content and end in content:
            continue
        block = f"{start}\n{end}\n"
        if not content.endswith("\n"):
            content += "\n"
        content += "\n" + block
    return content


def get_anchor_token_estimate(content: str, anchor_name: str) -> int:
    section = extract_between_anchors(content, anchor_name)
    if section is None:
        return 0
    return max(1, len(section) // 4)


def load_and_replace_anchor(path: Path, anchor_name: str, new_content: str, *, encoding: str = "utf-8") -> None:
    text = path.read_text(encoding=encoding)
    updated = replace_anchor_content(text, anchor_name, new_content)
    if updated != text:
        path.write_text(updated, encoding=encoding)
