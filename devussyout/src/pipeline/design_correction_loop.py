from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Tuple, List, Any, Optional

from .design_validator import DesignValidator, DesignValidationReport
from .llm_sanity_reviewer import LLMSanityReviewer, LLMSanityReviewResult


MAX_ITERATIONS = 3
CONFIDENCE_THRESHOLD = 0.8


@dataclass
class CorrectionChange:
    issue_code: str
    action: str
    before: str
    after: str
    explanation: str
    location: str = ""


@dataclass
class DesignCorrectionResult:
    design_text: str
    validation: DesignValidationReport
    review: LLMSanityReviewResult
    requires_human_review: bool = False
    max_iterations_reached: bool = False
    changes_made: List[CorrectionChange] = field(default_factory=list)
    iterations_used: int = 0


class DesignCorrectionLoop:
    def __init__(self) -> None:
        self._validator = DesignValidator()
        self._reviewer = LLMSanityReviewer()

    def run(self, design_text: str, complexity_profile: Optional[Any] = None) -> DesignCorrectionResult:
        current_design = design_text
        all_changes: List[CorrectionChange] = []

        for iteration in range(MAX_ITERATIONS):
            validation = self._validator.validate(current_design, complexity_profile=complexity_profile)
            review = self._reviewer.review(current_design, validation)

            if validation.is_valid and review.confidence > CONFIDENCE_THRESHOLD:
                return DesignCorrectionResult(design_text=current_design, validation=validation, review=review, changes_made=all_changes, iterations_used=iteration + 1)

            if not validation.auto_correctable:
                return DesignCorrectionResult(design_text=current_design, validation=validation, review=review, requires_human_review=True, changes_made=all_changes, iterations_used=iteration + 1)

            current_design, changes = self._apply_corrections(current_design, validation, review)
            all_changes.extend(changes)

        final_validation = self._validator.validate(current_design, complexity_profile=complexity_profile)
        final_review = self._reviewer.review(current_design, final_validation)
        return DesignCorrectionResult(design_text=current_design, validation=final_validation, review=final_review, max_iterations_reached=True, changes_made=all_changes, iterations_used=MAX_ITERATIONS)

    def _apply_corrections(self, design_text: str, validation: DesignValidationReport, review: LLMSanityReviewResult) -> Tuple[str, List[CorrectionChange]]:
        changes: List[CorrectionChange] = []
        footer_lines = ["\n\n---", "Corrections applied based on validation checks."]

        for issue in validation.issues:
            if issue.auto_correctable:
                footer_lines.append(f"- Resolved: {issue.code}")
                changes.append(CorrectionChange(issue_code=issue.code, action="added", before="", after=f"[Resolved: {issue.code}]", explanation=f"Auto-corrected issue: {issue.message}"))

        if review.risks:
            footer_lines.append("- Remaining risks: " + ", ".join(review.risks))

        return design_text + "\n" + "\n".join(footer_lines), changes

# Simple LLM-powered correction scaffold (uses an LLM client when provided)
DESIGN_CORRECTION_PROMPT = """IMPORTANT OUTPUT RULES (STRICT):\n1. Output ONLY valid JSON.\n... (truncated for brevity)"""
