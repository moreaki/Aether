#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


INTERRUPT_FILE_ORDER = [chr(code) for code in range(ord("A"), ord("R") + 1)]
INTERRUPT_FILE_PRIORITY = {name: index for index, name in enumerate(INTERRUPT_FILE_ORDER)}

KNOWN_SECTION_LABELS = {
    "desc",
    "note",
    "notes",
    "return",
    "returns",
    "seealso",
    "installcheck",
    "index",
    "warning",
    "warnings",
    "bugs",
    "bug",
}

HEADER_RE = re.compile(r"^INT ([0-9A-F]{2})h?\b", re.IGNORECASE)
SECTION_RE = re.compile(r"^([A-Za-z][A-Za-z0-9 /+_-]*):\s*(.*)$")
SELECTOR_RE = re.compile(r"^\s*([A-Z]{1,3}(?::[A-Z]{1,3})?)\s*=\s*(.+?)\s*$")


@dataclass(frozen=True)
class SelectorValue:
    register: str
    value: int
    text: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a structured RBIL interrupt catalog from local INTER61* sources."
    )
    parser.add_argument(
        "--input-root",
        default="input",
        help="Directory containing the inter61* folders",
    )
    parser.add_argument(
        "--output",
        default="Sources/Aether/Resources/Reference/rbil_interrupt_reference.json",
        help="Output JSON path",
    )
    return parser.parse_args()


def iter_interrupt_files(input_root: Path) -> Iterable[Path]:
    files = sorted(
        input_root.glob("inter61*/INTERRUP.*"),
        key=lambda path: (
            path.parent.name,
            INTERRUPT_FILE_PRIORITY.get(path.suffix.lstrip("."), 999),
            path.name,
        ),
    )
    return files


def parse_immediate(value_text: str) -> int | None:
    text = value_text.strip()
    if not text:
        return None

    if re.fullmatch(r"[0-9A-F]+h", text, re.IGNORECASE):
        return int(text[:-1], 16)
    if text.lower().startswith("0x") and re.fullmatch(r"0x[0-9a-f]+", text.lower()):
        return int(text[2:], 16)
    if re.fullmatch(r"\d+", text):
        return int(text, 10)

    return None


def normalize_space(text: str) -> str:
    return " ".join(text.replace("\t", " ").split())


def parse_sections(lines: list[str]) -> tuple[list[str], dict[str, list[str]]]:
    preamble: list[str] = []
    sections: dict[str, list[str]] = {}
    current_label: str | None = None

    for raw in lines:
        line = raw.rstrip()
        if not line.strip():
            continue

        section_match = SECTION_RE.match(line)
        if section_match and section_match.group(1).strip().lower() in KNOWN_SECTION_LABELS:
            current_label = section_match.group(1).strip().lower()
            sections.setdefault(current_label, [])
            initial = section_match.group(2).strip()
            if initial:
                sections[current_label].append(initial)
            continue

        if current_label:
            sections[current_label].append(line.strip())
        else:
            preamble.append(line)

    return preamble, sections


def parse_selector_values(preamble: list[str]) -> list[SelectorValue]:
    selectors: list[SelectorValue] = []

    for line in preamble:
        match = SELECTOR_RE.match(line)
        if not match:
            continue

        register = match.group(1).strip().upper()
        raw_value = normalize_space(match.group(2))
        immediate = parse_immediate(raw_value)
        if immediate is None:
            continue

        selectors.append(SelectorValue(register=register, value=immediate, text=raw_value))

    return selectors


def selector_text(selectors: list[SelectorValue]) -> str | None:
    if not selectors:
        return None
    return "/".join(f"{selector.register}={selector.text}" for selector in selectors)


def primary_service(selectors: list[SelectorValue]) -> tuple[str | None, int | None]:
    for preferred in ("AX", "AH"):
        for selector in selectors:
            if selector.register == preferred:
                return preferred, selector.value
    return None, None


def join_section_lines(values: list[str]) -> str | None:
    cleaned = [normalize_space(value) for value in values if value.strip()]
    if not cleaned:
        return None
    return " ".join(cleaned)


def parse_see_also(section_text: str | None) -> list[str]:
    if not section_text:
        return []
    parts = [normalize_space(part) for part in section_text.split(",")]
    return [part for part in parts if part]


def make_lookup_key(vector: int, selector: str | None) -> str:
    base = f"INT {vector:02X}h"
    return f"{base}/{selector}" if selector else base


def fallback_summary_from_header(header: str, vector: int) -> str | None:
    prefix = re.compile(rf"^INT {vector:02X}h?\s*(?:[A-Z]\s*)?-\s*", re.IGNORECASE)
    cleaned = prefix.sub("", header).strip()
    return cleaned or None


def extract_entries(path: Path) -> list[dict]:
    lines = path.read_text(errors="ignore").splitlines()
    entries: list[dict] = []

    index = 0
    while index < len(lines):
        divider = lines[index]
        if not divider.startswith("--------") or divider.startswith("--------!"):
            index += 1
            continue

        next_index = index + 1
        while next_index < len(lines) and not lines[next_index].strip():
            next_index += 1
        if next_index >= len(lines) or not lines[next_index].startswith("INT "):
            index += 1
            continue

        header = lines[next_index].rstrip()
        header_match = HEADER_RE.match(header)
        if not header_match:
            index += 1
            continue

        vector = int(header_match.group(1), 16)
        category = divider[8] if len(divider) > 8 and divider[8] != "-" else None

        body_index = next_index + 1
        body_lines: list[str] = []
        while body_index < len(lines) and not lines[body_index].startswith("--------"):
            body_lines.append(lines[body_index])
            body_index += 1

        preamble, sections = parse_sections(body_lines)
        selectors = parse_selector_values(preamble)
        selector_string = selector_text(selectors)
        service_register, service_value = primary_service(selectors)

        summary = join_section_lines(sections.get("desc", [])) or fallback_summary_from_header(header, vector)

        entry = {
            "lookupKey": make_lookup_key(vector, selector_string),
            "vector": vector,
            "category": category,
            "header": header,
            "selector": selector_string,
            "selectors": [
                {"register": selector.register, "value": selector.value, "text": selector.text}
                for selector in selectors
            ],
            "primaryServiceRegister": service_register,
            "primaryService": service_value,
            "summary": summary,
            "returns": join_section_lines(sections.get("return", []) or sections.get("returns", [])),
            "notes": [
                normalize_space(note)
                for note in sections.get("note", []) + sections.get("notes", [])
                if note.strip()
            ],
            "seeAlso": parse_see_also(join_section_lines(sections.get("seealso", []))),
            "sourceFile": path.name,
            "sourceLine": next_index + 1,
        }
        entries.append(entry)
        index = body_index

    return entries


def main() -> int:
    args = parse_args()
    input_root = Path(args.input_root)
    output_path = Path(args.output)

    files = list(iter_interrupt_files(input_root))
    if not files:
        raise SystemExit(f"No INTERRUP.* files found under {input_root}")

    entries: list[dict] = []
    for path in files:
        entries.extend(extract_entries(path))

    catalog = {
        "version": 1,
        "release": "61",
        "sources": [
            {
                "id": "rbil_release_61",
                "title": "Ralf Brown Interrupt List Release 61",
                "url": "https://www.cs.cmu.edu/~ralf/files.html",
            },
            {
                "id": "inter61_local",
                "title": "Local INTER61 text archive imported into Aether input/",
                "url": "local://input/inter61*",
            },
        ],
        "entries": entries,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(catalog, indent=2, sort_keys=False) + "\n")

    print(f"Generated {len(entries)} entries from {len(files)} files into {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
