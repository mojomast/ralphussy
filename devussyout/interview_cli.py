#!/usr/bin/env python3
"""CLI entry point for the interview-based devplan generation pipeline.

This script provides a command-line interface for running the continuous
LLM chat interview for generating development plans.

Usage:
    # Interactive mode (default)
    python interview_cli.py
    
    # With model specification
    python interview_cli.py --model opencode/claude-sonnet-4-5
    
    # Quick mode (skip to specific requirements)
    python interview_cli.py --project "my-api" --languages "Python,TypeScript" --requirements "Build a REST API"
    
    # Full automated mode
    python interview_cli.py --project "my-api" --languages "Python" --requirements "..." --no-interactive
"""

import argparse
import asyncio
import sys
import os

# Add the src directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from interview.interview_manager import InterviewManager, InterviewConfig


async def main():
    parser = argparse.ArgumentParser(
        description="Interactive devplan generation through LLM chat",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Start interactive interview
  python interview_cli.py

  # Start with a specific model
  python interview_cli.py --model opencode/claude-sonnet-4-5

  # Quick start with project details
  python interview_cli.py --project "my-project" --languages "Python,FastAPI"

  # Full automated mode (no chat, just generate)
  python interview_cli.py --project "my-api" --languages "Python" --requirements "Build a REST API" --no-interactive
        """
    )
    
    parser.add_argument(
        "--model", "-m",
        default="",
        help="Model to use (e.g., 'opencode/claude-sonnet-4-5' or just 'claude-sonnet-4-5')"
    )
    parser.add_argument(
        "--provider", "-p",
        default="",
        help="LLM provider (e.g., 'opencode', 'anthropic'). Extracted from model if not specified."
    )
    parser.add_argument(
        "--project",
        default=None,
        help="Project name (skips asking for it)"
    )
    parser.add_argument(
        "--languages",
        default=None,
        help="Comma-separated list of programming languages"
    )
    parser.add_argument(
        "--requirements",
        default=None,
        help="Project requirements description"
    )
    parser.add_argument(
        "--frameworks",
        default=None,
        help="Comma-separated list of frameworks"
    )
    parser.add_argument(
        "--no-interactive",
        action="store_true",
        help="Run in automated mode (requires --project, --languages, --requirements)"
    )
    parser.add_argument(
        "--save-dir",
        default=None,
        help="Directory to save output files (default: ~/.ralph/devplans)"
    )
    parser.add_argument(
        "--no-streaming",
        action="store_true",
        help="Disable streaming output"
    )
    
    args = parser.parse_args()
    
    # Parse model/provider
    provider = args.provider
    model = args.model
    
    if "/" in model and not provider:
        parts = model.split("/", 1)
        provider = parts[0]
    
    # Create config
    from pathlib import Path
    config = InterviewConfig(
        provider=provider,
        model=model,
        streaming=not args.no_streaming,
        save_dir=Path(args.save_dir) if args.save_dir else Path.home() / ".ralph" / "devplans",
    )
    
    # Create manager
    manager = InterviewManager(config)
    
    # Set up streaming output
    if not args.no_streaming:
        def on_token(token: str) -> None:
            print(token, end="", flush=True)
        manager.set_on_token(on_token)
    
    def on_progress(progress: dict) -> None:
        stage = progress.get("stage", "")
        pct = progress.get("progress_percent", 0)
        msg = progress.get("message", "")
        if msg:
            print(f"\n[{stage}] {pct}% - {msg}")
    
    manager.set_on_progress(on_progress)
    
    # Determine mode
    if args.no_interactive:
        # Automated mode - requires all parameters
        if not args.project or not args.languages or not args.requirements:
            print("Error: --no-interactive requires --project, --languages, and --requirements")
            sys.exit(1)
        
        # Build initial context and run
        manager._project_name = args.project
        manager._requirements = {
            "project_name": args.project,
            "languages": [l.strip() for l in args.languages.split(",")],
            "frameworks": [f.strip() for f in args.frameworks.split(",")] if args.frameworks else [],
            "requirements": args.requirements,
        }
        
        # Skip interview, go directly to design generation
        from interview.stage_coordinator import Stage
        manager.coordinator.mark_complete(Stage.INTERVIEW, manager._requirements)
        manager.coordinator.advance_stage()
        
        print(f"Generating devplan for: {args.project}")
        print("=" * 50)
        
        # Generate design
        response = await manager._generate_design()
        print(f"\n{response}\n")
        
        # Continue through stages
        for _ in range(4):  # design, devplan, detailed, handoff
            response = await manager._complete_current_stage()
            print(f"\n{response}\n")
            
            if manager.is_complete:
                break
        
        result = manager.get_result()
        print(f"\nOutput saved to: {result.output_dir}")
        
    else:
        # Interactive mode
        initial_message = None
        
        # Build initial message from provided args
        if args.project:
            initial_message = f"I want to build a project called {args.project}"
            if args.languages:
                initial_message += f" using {args.languages}"
            if args.requirements:
                initial_message += f". {args.requirements}"
        
        # Start interview
        response = await manager.start(initial_message)
        print(f"\n{response}\n")
        
        # Interactive loop
        while not manager.is_complete:
            try:
                user_input = input("> ").strip()
                if not user_input:
                    continue
                
                if user_input.lower() in ["/quit", "/exit", "quit", "exit"]:
                    print("Exiting. Progress not saved.")
                    break
                
                response = await manager.chat(user_input)
                print(f"\n{response}\n")
                
            except KeyboardInterrupt:
                print("\n\nInterrupted. Commands: /save, /status, /done, /quit")
            except EOFError:
                print("\nEOF received. Exiting.")
                break
        
        if manager.is_complete:
            result = manager.get_result()
            print(f"\nInterview complete!")
            print(f"Output saved to: {result.output_dir}")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nExiting.")
        sys.exit(0)
