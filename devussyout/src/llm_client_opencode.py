"""OpenCode LLM client for devussy pipeline.

This module implements an LLM client that uses the opencode CLI tool
for generating completions. It supports provider/model selection and
both synchronous and streaming modes.
"""

from __future__ import annotations

import asyncio
import json
import sys
import os
from typing import Any, Callable, Optional

# Set up paths for standalone execution
_this_dir = os.path.dirname(os.path.abspath(__file__))
if _this_dir not in sys.path:
    sys.path.insert(0, _this_dir)

# Now import using simple names
from llm_client import LLMClient


class OpenCodeConfig:
    """Configuration for OpenCode LLM client."""
    
    def __init__(
        self,
        provider: str = "",
        model: str = "",
        streaming_enabled: bool = False,
        max_concurrent_requests: int = 3,
        timeout: int = 300,
        server_url: Optional[str] = None,
    ):
        self.provider = provider
        self.model = model
        self.streaming_enabled = streaming_enabled
        self.max_concurrent_requests = max_concurrent_requests
        self.timeout = timeout
        self.server_url = server_url


class OpenCodeLLMClient(LLMClient):
    """LLM client using opencode CLI for devussy pipeline.
    
    This client wraps the opencode CLI tool to provide LLM completions
    for the devussy devplan generation pipeline. It supports:
    - Provider selection (anthropic, openai, etc.)
    - Model selection
    - JSON format output parsing
    - Timeout handling
    
    Example usage:
        config = OpenCodeConfig(provider="anthropic", model="claude-sonnet-4")
        client = OpenCodeLLMClient(config)
        response = await client.generate_completion("Write hello world in Python")
    """

    def __init__(self, config: Optional[OpenCodeConfig] = None, provider: str = "", model: str = ""):
        """Initialize the OpenCode LLM client.
        
        Args:
            config: OpenCodeConfig instance with settings
            provider: Provider name (overrides config if provided)
            model: Model name (overrides config if provided)
        """
        # Handle both config-based and direct parameter initialization
        if config is None:
            config = OpenCodeConfig(provider=provider, model=model)
        
        super().__init__(config)
        self.provider = provider or getattr(config, 'provider', '')
        self.model = model or getattr(config, 'model', '')
        self.timeout = getattr(config, 'timeout', 300)
        self.streaming_enabled = getattr(config, 'streaming_enabled', False)
        self.server_url = getattr(config, 'server_url', None)

    def _build_command(self) -> list[str]:
        """Build the opencode command with appropriate flags.
        
        Returns:
            List of command arguments for subprocess.
        """
        cmd = ["opencode", "run", "--format", "json"]
        
        # Build model string (provider/model or just model)
        full_model = ""
        if self.model:
            if "/" in self.model:
                # Model already includes provider
                full_model = self.model
            elif self.provider:
                full_model = f"{self.provider}/{self.model}"
            else:
                full_model = self.model
        
        if full_model:
            cmd.extend(["--model", full_model])
        
        return cmd

    async def generate_completion(self, prompt: str, **kwargs: Any) -> str:
        """Generate a completion using opencode CLI or server mode.
        
        Args:
            prompt: The prompt to send to the LLM
            **kwargs: Additional arguments (currently unused)
            
        Returns:
            The generated text response
            
        Raises:
            RuntimeError: If opencode command fails
            ValueError: If response parsing fails
        """
        if self.server_url:
            return await self._generate_via_server(prompt)

        cmd = self._build_command()
        
        try:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            
            # Send prompt via stdin and wait for completion
            stdout, stderr = await asyncio.wait_for(
                process.communicate(prompt.encode('utf-8')),
                timeout=self.timeout
            )
            
            exit_code = process.returncode
            
            if exit_code != 0:
                error_msg = stderr.decode('utf-8') if stderr else "Unknown error"
                raise RuntimeError(
                    f"opencode failed with exit code {exit_code}: {error_msg[:500]}"
                )
            
            # Parse JSON response
            output_text = stdout.decode('utf-8').strip()
            return self._extract_text_from_response(output_text)
            
        except asyncio.TimeoutError:
            raise RuntimeError(
                f"opencode command timed out after {self.timeout} seconds"
            )
        except FileNotFoundError:
            raise RuntimeError(
                "opencode command not found. Ensure opencode is installed and in PATH."
            )

    async def _generate_via_server(self, prompt: str) -> str:
        """Generate completion using persistent server connection.

        Args:
            prompt: The prompt to send

        Returns:
            The generated text
        """
        try:
            import aiohttp
        except ImportError:
            raise ImportError("aiohttp is required for server mode. Install it with: pip install aiohttp")

        payload = {
            "prompt": prompt,
            "format": "json"
        }

        # Build model string (provider/model or just model)
        full_model = ""
        if self.model:
            if "/" in self.model:
                full_model = self.model
            elif self.provider:
                full_model = f"{self.provider}/{self.model}"
            else:
                full_model = self.model

        if full_model:
            payload["model"] = full_model

        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    self.server_url,
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=self.timeout)
                ) as response:
                    if response.status != 200:
                        error_text = await response.text()
                        raise RuntimeError(
                            f"Server returned status {response.status}: {error_text[:500]}"
                        )

                    response_text = await response.text()
                    return self._extract_text_from_response(response_text)

        except asyncio.TimeoutError:
            raise RuntimeError(f"Server request timed out after {self.timeout} seconds")
        except Exception as e:
            raise RuntimeError(f"Server request failed: {str(e)}")

    def _extract_text_from_response(self, response: str) -> str:
        """Extract text content from opencode JSON response.
        
        The opencode CLI with --format json returns a JSON object
        with a "text" field containing the LLM response.
        
        Args:
            response: Raw JSON string from opencode
            
        Returns:
            Extracted text content
            
        Raises:
            ValueError: If JSON parsing fails or text field is missing
        """
        if not response:
            return ""
        
        try:
            # Try to parse as JSON
            data = json.loads(response)
            
            # Handle different response formats
            if isinstance(data, dict):
                # Standard format: {"text": "..."}
                if "text" in data:
                    return data["text"]
                # Alternative format: {"content": "..."}
                if "content" in data:
                    return data["content"]
                # Alternative format: {"message": {"content": "..."}}
                if "message" in data and isinstance(data["message"], dict):
                    return data["message"].get("content", "")
                # Alternative format: {"choices": [{"message": {"content": "..."}}]}
                if "choices" in data and data["choices"]:
                    choice = data["choices"][0]
                    if isinstance(choice, dict) and "message" in choice:
                        return choice["message"].get("content", "")
            
            # If we couldn't extract text, return raw response
            return response
            
        except json.JSONDecodeError:
            # If not valid JSON, return as-is (might be plain text)
            return response

    async def generate_completion_streaming(
        self,
        prompt: str,
        callback: Callable[[str], Any],
        **kwargs: Any
    ) -> str:
        """Generate completion with streaming callback.
        
        Note: opencode CLI streaming support is limited.
        This implementation falls back to non-streaming and calls
        the callback once with the full response.
        
        Args:
            prompt: The prompt to send
            callback: Function to call with streamed tokens
            **kwargs: Additional arguments
            
        Returns:
            The complete generated text
        """
        # For now, use non-streaming as fallback
        # opencode may not support true streaming via CLI
        text = await self.generate_completion(prompt, **kwargs)
        
        if callback:
            try:
                # Check if callback is async
                if asyncio.iscoroutinefunction(callback):
                    await callback(text)
                else:
                    callback(text)
            except Exception:
                # Don't let callback errors break the flow
                pass
        
        return text


# Convenience function for quick client creation
def create_opencode_client(
    provider: str = "",
    model: str = "",
    timeout: int = 300,
    server_url: Optional[str] = None
) -> OpenCodeLLMClient:
    """Create an OpenCode LLM client with the given settings.
    
    Args:
        provider: LLM provider (anthropic, openai, etc.)
        model: Model name
        timeout: Timeout in seconds
        server_url: URL of opencode server (optional)
        
    Returns:
        Configured OpenCodeLLMClient instance
    """
    config = OpenCodeConfig(
        provider=provider,
        model=model,
        timeout=timeout,
        server_url=server_url
    )
    return OpenCodeLLMClient(config)
