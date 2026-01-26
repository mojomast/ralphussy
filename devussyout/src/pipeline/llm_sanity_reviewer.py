"""Mock and LLM-backed sanity reviewer."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import List, Any


@dataclass
class LLMSanityReviewResult:
    confidence: float
    notes: str
    risks: List[str]


@dataclass
class HallucinationIssue:
    type: str
    text: str
    note: str


@dataclass
class ScopeAlignment:
    score: float
    missing_requirements: List[str] = field(default_factory=list)
    over_engineered: List[str] = field(default_factory=list)
    under_engineered: List[str] = field(default_factory=list)


@dataclass
class Risk:
    severity: str
    category: str
    description: str
    mitigation: str


@dataclass
class LLMSanityReviewResultDetailed:
    confidence: float
    overall_assessment: str
    coherence_score: float
    coherence_notes: str
    hallucination_passed: bool
    hallucination_issues: List[HallucinationIssue] = field(default_factory=list)
    scope_alignment: ScopeAlignment | None = None
    risks: List[Risk] = field(default_factory=list)
    suggestions: List[str] = field(default_factory=list)
    summary: str = ""


class LLMSanityReviewer:
    def review(self, design_text: str, validation_report: Any) -> LLMSanityReviewResult:
        if validation_report.is_valid:
            confidence = 0.9
            notes = "Design passes all rule-based checks."
            risks: List[str] = []
        else:
            non_auto = [i for i in validation_report.issues if not i.auto_correctable]
            if non_auto:
                confidence = 0.5
            else:
                confidence = 0.7
            notes = "Design has validation issues; manual review recommended."
            risks = [issue.code for issue in validation_report.issues]

        return LLMSanityReviewResult(confidence=confidence, notes=notes, risks=risks)
