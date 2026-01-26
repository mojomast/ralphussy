"""Template loading and rendering using Jinja2."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any

from jinja2 import Environment, FileSystemLoader, Template


def _templates_dir() -> Path:
    # Resolve templates directory relative to this file
    return Path(__file__).resolve().parents[1] / "templates"


@lru_cache(maxsize=1)
def _env() -> Environment:
    loader = FileSystemLoader(str(_templates_dir()))
    env = Environment(loader=loader, autoescape=False, trim_blocks=True, lstrip_blocks=True)
    env.globals["enumerate"] = enumerate
    env.globals["len"] = len
    return env


def load_template(name: str) -> Template:
    tpl = _env().get_template(name)
    return tpl


def render_template(name: str, context: dict[str, Any]) -> str:
    try:
        import json
        from datetime import datetime

        log_dir = Path(__file__).resolve().parents[1] / "DevDocs" / "JINJA_DATA_SAMPLES"
        log_dir.mkdir(parents=True, exist_ok=True)

        safe_name = name.replace("/", "_").replace("\\", "_")
        log_file = log_dir / f"{safe_name}.json"

        def default_serializer(obj):
            if isinstance(obj, datetime):
                return obj.isoformat()
            try:
                return obj.model_dump()
            except AttributeError:
                pass
            try:
                return obj.dict()
            except AttributeError:
                pass
            return str(obj)

        with open(log_file, "w", encoding="utf-8") as f:
            json.dump(context, f, indent=2, default=default_serializer)
    except Exception:
        pass

    return load_template(name).render(**context)
