"""JSON extraction utilities for parsing structured data from LLM responses.

This module provides tools for extracting structured JSON data from LLM responses,
which may contain JSON embedded in markdown code blocks, natural language, or other formats.
"""

from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional, Type, TypeVar
from pydantic import BaseModel


T = TypeVar('T', bound=BaseModel)


class JSONExtractor:
    """Extract structured data from LLM responses.
    
    Handles various response formats:
    - Pure JSON
    - JSON in markdown code blocks (```json ... ```)
    - JSON log entries (streaming format)
    - Partial JSON with natural language
    
    Example:
        extractor = JSONExtractor()
        
        # Extract from markdown
        response = '''Here's the data:
        ```json
        {"name": "test", "value": 42}
        ```
        '''
        data = extractor.extract_json(response)
        # Returns: {"name": "test", "value": 42}
    """
    
    # Common JSON patterns in LLM responses
    JSON_BLOCK_PATTERN = re.compile(r'```(?:json)?\s*\n?(.*?)\n?```', re.DOTALL | re.IGNORECASE)
    JSON_OBJECT_PATTERN = re.compile(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', re.DOTALL)
    JSON_ARRAY_PATTERN = re.compile(r'\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\]', re.DOTALL)
    
    def __init__(self):
        """Initialize the JSON extractor."""
        pass
    
    def extract_json(self, response: str, expect_type: str = "object") -> Optional[Dict[str, Any] | List[Any]]:
        """Extract JSON from an LLM response.
        
        Tries multiple extraction strategies:
        1. Direct JSON parsing
        2. Extract from markdown code blocks
        3. Extract from JSON log entries
        4. Find JSON object/array in text
        
        Args:
            response: Raw LLM response text
            expect_type: "object" for dict, "array" for list
            
        Returns:
            Extracted JSON data or None if extraction fails
        """
        if not response or not response.strip():
            return None
        
        # Strategy 1: Try direct JSON parsing
        result = self._try_direct_parse(response.strip())
        if result is not None:
            return result
        
        # Strategy 2: Extract from markdown code blocks
        result = self._extract_from_code_blocks(response)
        if result is not None:
            return result
        
        # Strategy 3: Extract from JSON log entries
        result = self._extract_from_log_entries(response)
        if result is not None:
            # Log entries usually contain text, try to parse it
            if isinstance(result, str):
                parsed = self._try_direct_parse(result)
                if parsed is not None:
                    return parsed
        
        # Strategy 4: Find JSON in text
        if expect_type == "array":
            result = self._find_json_array(response)
        else:
            result = self._find_json_object(response)
        
        return result
    
    def extract_to_model(self, response: str, model_class: Type[T]) -> Optional[T]:
        """Extract JSON and parse into a Pydantic model.
        
        Args:
            response: Raw LLM response
            model_class: Pydantic model class to parse into
            
        Returns:
            Instance of model_class or None if extraction/parsing fails
        """
        data = self.extract_json(response)
        if data is None or not isinstance(data, dict):
            return None
        
        try:
            return model_class.model_validate(data)
        except Exception:
            return None
    
    def extract_interview_data(self, response: str) -> Dict[str, Any]:
        """Extract interview/requirements data from LLM response.
        
        Handles the special format used in interview responses where
        the LLM provides both conversation and a JSON summary.
        
        Args:
            response: Interview response from LLM
            
        Returns:
            Dictionary with extracted project data
        """
        # Try to find JSON summary section
        json_data = self.extract_json(response)
        if json_data and isinstance(json_data, dict):
            return json_data
        
        # Fall back to regex extraction for key fields
        return self._extract_fields_via_regex(response)
    
    def _try_direct_parse(self, text: str) -> Optional[Dict[str, Any] | List[Any]]:
        """Try to parse text directly as JSON."""
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return None
    
    def _extract_from_code_blocks(self, text: str) -> Optional[Dict[str, Any] | List[Any]]:
        """Extract JSON from markdown code blocks."""
        matches = self.JSON_BLOCK_PATTERN.findall(text)
        
        for match in matches:
            result = self._try_direct_parse(match.strip())
            if result is not None:
                return result
        
        return None
    
    def _extract_from_log_entries(self, response: str) -> Optional[str]:
        """Extract text from JSON log entries (streaming format).
        
        The response may contain JSON log entries from streaming sessions like:
        {"type":"text","timestamp":...,"part":{"type":"text","text":"actual content..."}}
        """
        if not response.strip().startswith('{'):
            return None
        
        extracted_parts: List[str] = []
        lines = response.split('\n')
        
        for line in lines:
            line = line.strip()
            if not line or not line.startswith('{'):
                continue
            
            try:
                entry = json.loads(line)
                if isinstance(entry, dict):
                    entry_type = entry.get("type", "")
                    part = entry.get("part", {})
                    
                    if entry_type == "text" and isinstance(part, dict):
                        text_content = part.get("text", "")
                        if text_content:
                            extracted_parts.append(text_content)
                    elif "text" in entry and isinstance(entry["text"], str):
                        extracted_parts.append(entry["text"])
            except json.JSONDecodeError:
                continue
        
        if extracted_parts:
            return "\n".join(extracted_parts)
        
        return None
    
    def _find_json_object(self, text: str) -> Optional[Dict[str, Any]]:
        """Find and extract a JSON object from text."""
        # Try to find the largest valid JSON object
        matches = self.JSON_OBJECT_PATTERN.findall(text)
        
        valid_objects = []
        for match in matches:
            result = self._try_direct_parse(match)
            if result is not None and isinstance(result, dict):
                valid_objects.append((len(match), result))
        
        if valid_objects:
            # Return the largest valid object
            valid_objects.sort(key=lambda x: x[0], reverse=True)
            return valid_objects[0][1]
        
        return None
    
    def _find_json_array(self, text: str) -> Optional[List[Any]]:
        """Find and extract a JSON array from text."""
        matches = self.JSON_ARRAY_PATTERN.findall(text)
        
        for match in matches:
            result = self._try_direct_parse(match)
            if result is not None and isinstance(result, list):
                return result
        
        return None
    
    def _extract_fields_via_regex(self, text: str) -> Dict[str, Any]:
        """Extract known fields using regex patterns.
        
        Fallback method when JSON extraction fails.
        """
        result: Dict[str, Any] = {}
        
        # Common patterns for interview data
        patterns = {
            "project_name": [
                r"[Pp]roject\s*[Nn]ame[:\s]+[\"']?([^\"'\n]+)[\"']?",
                r"[Nn]ame[:\s]+[\"']?([^\"'\n]+)[\"']?",
            ],
            "languages": [
                r"[Ll]anguages?[:\s]+([^\n]+)",
                r"[Pp]rogramming\s+[Ll]anguages?[:\s]+([^\n]+)",
            ],
            "frameworks": [
                r"[Ff]rameworks?[:\s]+([^\n]+)",
            ],
            "requirements": [
                r"[Rr]equirements?[:\s]+([^\n]+(?:\n(?![\w]+:)[^\n]+)*)",
            ],
            "apis": [
                r"[Aa][Pp][Ii]s?[:\s]+([^\n]+)",
                r"[Ee]xternal\s+[Ss]ervices?[:\s]+([^\n]+)",
            ],
        }
        
        for field, field_patterns in patterns.items():
            for pattern in field_patterns:
                match = re.search(pattern, text)
                if match:
                    value = match.group(1).strip()
                    # Handle list fields
                    if field in ["languages", "frameworks", "apis"]:
                        # Split by common delimiters
                        items = re.split(r'[,;]\s*', value)
                        result[field] = [item.strip() for item in items if item.strip()]
                    else:
                        result[field] = value
                    break
        
        return result
    
    def extract_phase_data(self, response: str, phase_number: int) -> List[Dict[str, Any]]:
        """Extract step data from a detailed phase response.
        
        Parses the numbered step format:
        N.X: Step description
        - Detail 1
        - Detail 2
        
        Args:
            response: LLM response with phase details
            phase_number: The phase number to look for
            
        Returns:
            List of step dictionaries with number, description, details
        """
        steps = []
        lines = response.split("\n")
        step_pattern = re.compile(rf"^{phase_number}\.(\d+):?\s*(.+)$", re.IGNORECASE)
        
        current_step = None
        current_details = []
        
        for line in lines:
            stripped = line.strip()
            step_match = step_pattern.match(stripped)
            
            if step_match:
                # Save previous step
                if current_step is not None:
                    steps.append({
                        "number": current_step["number"],
                        "description": current_step["description"],
                        "details": current_details[:],
                    })
                
                sub_num = int(step_match.group(1))
                description = step_match.group(2).strip()
                
                current_step = {
                    "number": f"{phase_number}.{sub_num}",
                    "description": description,
                }
                current_details = []
            
            elif stripped.startswith("-") and current_step:
                detail = stripped[1:].strip()
                if detail:
                    current_details.append(detail)
        
        # Don't forget the last step
        if current_step is not None:
            steps.append({
                "number": current_step["number"],
                "description": current_step["description"],
                "details": current_details[:],
            })
        
        return steps
    
    def extract_design_sections(self, response: str) -> Dict[str, Any]:
        """Extract sections from a project design response.
        
        Parses markdown sections like:
        ## Objectives
        - Objective 1
        - Objective 2
        
        Args:
            response: Project design response from LLM
            
        Returns:
            Dictionary with section data
        """
        result: Dict[str, Any] = {
            "objectives": [],
            "tech_stack": [],
            "architecture_overview": "",
            "dependencies": [],
            "challenges": [],
            "mitigations": [],
        }
        
        lines = response.split("\n")
        current_section = None
        architecture_lines = []
        
        for line in lines:
            stripped = line.strip()
            
            # Check for section headers
            if "objective" in stripped.lower() and stripped.startswith("#"):
                current_section = "objectives"
                continue
            elif "technology stack" in stripped.lower() and stripped.startswith("#"):
                current_section = "tech_stack"
                continue
            elif "architecture" in stripped.lower() and stripped.startswith("#"):
                current_section = "architecture"
                architecture_lines = []
                continue
            elif "dependencies" in stripped.lower() and stripped.startswith("#"):
                current_section = "dependencies"
                continue
            elif "challenge" in stripped.lower() and stripped.startswith("#"):
                current_section = "challenges"
                continue
            elif stripped.startswith("#"):
                current_section = None
                continue
            
            # Extract content based on section
            if current_section and stripped.startswith("-"):
                content = stripped[1:].strip()
                if content:
                    if current_section == "objectives":
                        result["objectives"].append(content)
                    elif current_section == "tech_stack":
                        result["tech_stack"].append(content)
                    elif current_section == "dependencies":
                        result["dependencies"].append(content)
                    elif current_section == "challenges":
                        if any(kw in content.lower() for kw in ["mitigation", "solution", "address"]):
                            result["mitigations"].append(content)
                        else:
                            result["challenges"].append(content)
            elif current_section == "architecture" and stripped:
                architecture_lines.append(stripped)
        
        if architecture_lines:
            result["architecture_overview"] = "\n".join(architecture_lines)
        elif not result["architecture_overview"] and response:
            # Fallback: use entire response as architecture
            result["architecture_overview"] = response
        
        return result
