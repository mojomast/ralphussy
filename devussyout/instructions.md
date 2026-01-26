Quick implementation notes — how to reuse the exported Devussy pipeline in another project

This file gives a quick roadmap to integrate the pipeline pieces inside `devussyout/` into another repository.

1) Prerequisites
- Python 3.10+ (the code uses typed annotations and asyncio)
- Install minimal runtime packages:
  - `pip install jinja2 pydantic python-dotenv ruamel.yaml`

2) Copy the export
- Copy the whole `devussyout/` folder to your project root (or add it as a subpackage).
- Ensure `devussyout/templates/` is present and remains colocated with `devussyout/src/templates.py`.

3) Provide an LLM client
- Implement a concrete LLM client subclass of `devussyout/src/llm_client.LLMClient`.
- Required async method: `async def generate_completion(self, prompt: str, **kwargs) -> str`.
- Optional: `generate_completion_streaming(self, prompt, callback, **kwargs)` for streaming.

Minimal mock example (place in your project; not included here):
```py
from devussyout.src.llm_client import LLMClient

class MockLLM(LLMClient):
    async def generate_completion(self, prompt: str, **kwargs):
        # Return a deterministic sample response suitable for parsing tests
        return "Phase 1: Setup\n- Summary: Initialize repo\n"
```

4) Basic usage pattern
- Create generators and run them in async code:
```py
import asyncio
from devussyout.src.pipeline.project_design import ProjectDesignGenerator
from devussyout.src.pipeline.basic_devplan import BasicDevPlanGenerator
from devussyout.src.pipeline.detailed_devplan import DetailedDevPlanGenerator
from devussyout.src.concurrency import ConcurrencyManager

llm = MockLLM(config=type('C', (), {'max_concurrent_requests': 3, 'streaming_enabled': False}))
pdg = ProjectDesignGenerator(llm)
bdg = BasicDevPlanGenerator(llm)
cm = ConcurrencyManager(config=llm._config)
ddg = DetailedDevPlanGenerator(llm, cm)

async def run():
    design = await pdg.generate('MyApp', ['Python'], 'Requirements...')
    basic = await bdg.generate(design)
    detailed = await ddg.generate(basic, design.project_name, tech_stack=design.tech_stack)
    print(detailed.to_json())

asyncio.run(run())
```

5) Templates & prompts
- Jinja templates are in `devussyout/templates/`. `devussyout/src/templates.py` expects templates relative to that folder.
- You can edit templates to adapt prompt wording for your provider or product.

6) Config hints
- Some code references `devussyout/src/config.py` behavior (e.g. hivemind flags). You can either:
  1. Provide a tiny config-like object with the attributes used (e.g., `.hivemind.enabled`, `.hivemind.drone_count`, `.max_concurrent_requests`) OR
  2. Port the original `config.py` logic into your project and adapt environment variables.

7) Anchor helpers and handoff
- Use `devussyout/src/utils/anchor_utils.py` to safely read/update anchored regions in markdown (hand-off files expect anchors like `<!-- QUICK_STATUS_START -->`).

8) Testing & smoke checks
- Start with a `MockLLM` to validate parsing and template rendering before connecting real LLM credentials.
- Verify: templates render (`render_template('project_design.jinja', {...})`), parsing functions produce `DevPlan`/`ProjectDesign` objects.

9) Next steps (suggested)
1. Implement a real provider client (OpenAI, Aether, etc.).
2. Add a small smoke script (like the usage example above) and iterate on templates.
3. Optionally port `config.py` and provider clients for full feature parity.

If you want, I can add a small smoke test script and a `MockLLM` example inside `devussyout/` so you can run an end-to-end dry run — tell me and I will add it.
