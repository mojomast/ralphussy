"""HiveMind orchestration engine for swarm-based generation."""

import asyncio
import logging
import sys
import os
from typing import List, Optional, Any, Dict

# Set up paths for standalone execution
_this_dir = os.path.dirname(os.path.abspath(__file__))
_parent_dir = os.path.dirname(_this_dir)
if _this_dir not in sys.path:
    sys.path.insert(0, _this_dir)
if _parent_dir not in sys.path:
    sys.path.insert(0, _parent_dir)

# Now import using simple names (works both as package and standalone)
from llm_client import LLMClient
from templates import render_template

logger = logging.getLogger(__name__)


class HiveMindManager:
    def __init__(self, llm_client: LLMClient):
        self.llm_client = llm_client

    async def run_swarm(self, prompt: str, count: int = 3, temperature_jitter: bool = True, base_temperature: float = 0.7, drone_callbacks: Optional[List[Any]] = None, arbiter_callback: Optional[Any] = None, **llm_kwargs: Any) -> str:
        drone_responses = await self._execute_parallel(prompt, count, temperature_jitter, base_temperature, drone_callbacks=drone_callbacks, **llm_kwargs)
        arbiter_prompt = self._format_for_arbiter(prompt, drone_responses)
        final_response = await self._call_arbiter(arbiter_prompt, arbiter_callback=arbiter_callback, **llm_kwargs)
        return final_response

    async def _execute_parallel(self, prompt: str, count: int, temperature_jitter: bool, base_temperature: float, drone_callbacks: Optional[List[Any]] = None, **llm_kwargs: Any) -> List[str]:
        async def execute_drone(i: int):
            if temperature_jitter and count > 1:
                offset = (i / (count - 1) - 0.5) * 0.4 if count > 1 else 0
                temp = max(0.0, min(2.0, base_temperature + offset))
            else:
                temp = base_temperature

            drone_kwargs = llm_kwargs.copy()
            drone_kwargs["temperature"] = temp
            if "streaming_handler" in drone_kwargs:
                del drone_kwargs["streaming_handler"]

            callback = drone_callbacks[i] if drone_callbacks and i < len(drone_callbacks) else None

            if callback:
                response = await self.llm_client.generate_completion_streaming(prompt, callback=callback.on_token_async, **drone_kwargs)
                await callback.on_completion_async(response)
                return response
            else:
                response = await self.llm_client.generate_completion(prompt, **drone_kwargs)
                return response

        drone_responses = await asyncio.gather(*[execute_drone(i) for i in range(count)])
        return drone_responses

    def _format_for_arbiter(self, original_prompt: str, drone_responses: List[str]) -> str:
        drone_outputs = []
        for i, response in enumerate(drone_responses):
            drone_outputs.append({"id": i + 1, "content": response})

        context = {"original_prompt": original_prompt, "drones": drone_outputs}
        return render_template("hivemind_arbiter.jinja", context)

    async def _call_arbiter(self, prompt: str, arbiter_callback: Optional[Any] = None, **llm_kwargs: Any) -> str:
        arbiter_kwargs = llm_kwargs.copy()
        arbiter_kwargs["temperature"] = 0.2
        if "streaming_handler" in arbiter_kwargs:
            del arbiter_kwargs["streaming_handler"]

        if arbiter_callback:
            response = await self.llm_client.generate_completion_streaming(prompt, callback=arbiter_callback.on_token_async, **arbiter_kwargs)
            await arbiter_callback.on_completion_async(response)
            return response
        else:
            return await self.llm_client.generate_completion(prompt, **arbiter_kwargs)
