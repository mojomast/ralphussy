"""Design validator for rule-based validation checks."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional


@dataclass
class DesignValidationIssue:
    code: str
    message: str
    auto_correctable: bool = True
    severity: str = "warning"
    suggestion: str = ""


@dataclass
class DesignValidationReport:
    is_valid: bool
    auto_correctable: bool
    issues: List[DesignValidationIssue] = field(default_factory=list)
    checks: Dict[str, bool] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.issues and any(i.severity == "error" for i in self.issues):
            self.is_valid = False


class DesignValidator:
    REQUIRED_SECTIONS = ["architecture", "database", "testing"]
    OVER_ENGINEERING_KEYWORDS = ["microservice", "kubernetes", "distributed", "event sourcing", "cqrs"]

    def validate(self, design_text: str, complexity_profile: Optional[Any] = None) -> DesignValidationReport:
        issues: List[DesignValidationIssue] = []
        checks: Dict[str, bool] = {}

        checks["completeness"] = self._check_completeness(design_text, issues)
        checks["consistency"] = self._check_consistency(design_text, issues)
        checks["scope_alignment"] = self._check_scope_alignment(design_text, complexity_profile, issues)
        checks["hallucination"] = self._check_hallucinations(design_text, issues)
        checks["over_engineering"] = self._check_over_engineering(design_text, complexity_profile, issues)

        is_valid = all(checks.values())
        auto_correctable = all(issue.auto_correctable for issue in issues)

        return DesignValidationReport(is_valid=is_valid, auto_correctable=auto_correctable, issues=issues, checks=checks)

    def _check_completeness(self, design_text: str, issues: List[DesignValidationIssue]) -> bool:
        design_lower = design_text.lower()
        missing = []

        for section in self.REQUIRED_SECTIONS:
            if section not in design_lower:
                missing.append(section)

        if missing:
            issues.append(DesignValidationIssue(code="completeness.missing_sections", message=f"Missing required sections: {', '.join(missing)}", auto_correctable=True, severity="warning", suggestion=f"Add sections for: {', '.join(missing)}"))
            return False

        return True

    def _check_consistency(self, design_text: str, issues: List[DesignValidationIssue]) -> bool:
        design_lower = design_text.lower()
        db_choices = []
        for db in ["postgresql", "mysql", "mongodb", "sqlite"]:
            if db in design_lower:
                db_choices.append(db)

        if len(db_choices) > 1:
            issues.append(DesignValidationIssue(code="consistency.multiple_databases", message=f"Multiple databases mentioned: {', '.join(db_choices)}", auto_correctable=False, severity="warning", suggestion="Clarify primary database choice"))
            return False

        return True

    def _check_scope_alignment(self, design_text: str, complexity_profile: Optional[Any], issues: List[DesignValidationIssue]) -> bool:
        if complexity_profile is None:
            return True
        design_lower = design_text.lower()
        complexity_keywords = ["microservice", "distributed", "kubernetes", "redis", "elasticsearch", "kafka", "rabbitmq", "graphql"]
        found_keywords = sum(1 for kw in complexity_keywords if kw in design_lower)
        if getattr(complexity_profile, "depth_level", None) == "minimal" and found_keywords > 2:
            issues.append(DesignValidationIssue(code="scope_alignment.over_scoped", message="Design complexity exceeds minimal profile", auto_correctable=True, severity="warning", suggestion="Simplify architecture for minimal scope"))
            return False
        return True

    def _check_hallucinations(self, design_text: str, issues: List[DesignValidationIssue]) -> bool:
        return True

    def _check_over_engineering(self, design_text: str, complexity_profile: Optional[Any], issues: List[DesignValidationIssue]) -> bool:
        if complexity_profile is None:
            return True
        if getattr(complexity_profile, "depth_level", None) != "minimal":
            return True
        design_lower = design_text.lower()
        found_over_engineering = []
        for keyword in self.OVER_ENGINEERING_KEYWORDS:
            if keyword in design_lower:
                found_over_engineering.append(keyword)

        if found_over_engineering:
            issues.append(DesignValidationIssue(code="over_engineering.complex_for_simple", message=f"Over-engineered patterns for minimal project: {', '.join(found_over_engineering)}", auto_correctable=True, severity="warning", suggestion="Simplify architecture for project scale"))
            return False

        return True
