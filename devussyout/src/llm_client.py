"""Abstract LLM client interface for provider-agnostic usage.

This module defines a minimal async interface expected by the exported
pipeline stages. Concrete provider clients should implement these methods.
"""

from __future__ import annotations

import abc
import asyncio
from typing import Any, Callable, Iterable, List


class LLMClient(abc.ABC):
    """Abstract base class for all LLM clients.

    Concrete implementations should accept a configuration object in their
    constructor (e.g., an instance with `.llm`, `.retry`, and other fields).
    """

    def __init__(self, config: Any) -> None:
        self._config = config
        # Support streaming enabled flag if present in config
        self.streaming_enabled = getattr(config, "streaming_enabled", False)

    @abc.abstractmethod
    async def generate_completion(self, prompt: str, **kwargs: Any) -> str:
        """Generate a single completion for the provided prompt.

        Returns the generated text content from the provider.
        """

    async def generate_multiple(self, prompts: Iterable[str]) -> List[str]:
        """Generate completions for multiple prompts concurrently.
        """
        concurrency = getattr(self._config, "max_concurrent_requests", 5) or 5
        semaphore = asyncio.Semaphore(concurrency)

        async def _one(p: str) -> str:
            async with semaphore:
                return await self.generate_completion(p)

        return await asyncio.gather(*(_one(p) for p in prompts))

    def generate_completion_sync(self, prompt: str, **kwargs: Any) -> str:
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            loop = None

        if loop and loop.is_running():
            raise RuntimeError(
                "generate_completion_sync() called inside an active event loop. Use the async method instead."
            )

        return asyncio.run(self.generate_completion(prompt, **kwargs))

    async def generate_completion_streaming(self, prompt: str, callback: Callable[[str], Any], **kwargs: Any) -> str:
        """Default streaming implementation: simulate by chunking full response."""
        full_response = await self.generate_completion(prompt, **kwargs)

        # Import here to avoid circular imports if not needed
        try:
            from .streaming import StreamingSimulator

            simulator = StreamingSimulator()
            await simulator.simulate_streaming(full_response, callback)
        except Exception:
            # If streaming simulator not available, call callback once
            callback(full_response)

        return full_response
