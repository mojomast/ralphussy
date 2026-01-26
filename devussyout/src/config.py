"""Configuration management for devussy pipeline.

This module provides configuration loading with sensible defaults.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class HiveMindConfig:
    """Configuration for HiveMind swarm generation."""
    enabled: bool = False
    drone_count: int = 3
    temperature_jitter: float = 0.1


@dataclass
class Config:
    """Main configuration object."""
    hivemind: HiveMindConfig = field(default_factory=HiveMindConfig)


def load_config() -> Config:
    """Load configuration with defaults.
    
    Returns:
        Config object with default values.
    """
    return Config()
