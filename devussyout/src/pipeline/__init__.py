"""Pipeline stages exported for reuse."""

# Support both package-style and standalone imports
import sys
import os

# When imported directly (not as package), set up path for imports
_this_dir = os.path.dirname(os.path.abspath(__file__))
_parent_dir = os.path.dirname(_this_dir)

# Add both the pipeline dir and parent src dir to path for standalone execution
if _this_dir not in sys.path:
    sys.path.insert(0, _this_dir)
if _parent_dir not in sys.path:
    sys.path.insert(0, _parent_dir)

from project_design import ProjectDesignGenerator
from basic_devplan import BasicDevPlanGenerator
from detailed_devplan import DetailedDevPlanGenerator
from handoff_prompt import HandoffPromptGenerator

__all__ = [
    "ProjectDesignGenerator",
    "BasicDevPlanGenerator",
    "DetailedDevPlanGenerator",
    "HandoffPromptGenerator",
]
