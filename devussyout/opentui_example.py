#!/usr/bin/env python3
"""Example showing how OpenTUI interacts with the interview CLI.

This simulates the message-passing behavior of OpenTUI:
1. User types a message
2. OpenTUI invokes the CLI with the message
3. CLI processes and returns response
4. OpenTUI displays response
5. Repeat

This demonstrates that the CLI works without a real TTY.
"""

import subprocess
import sys
import os


def send_message(message: str) -> str:
    """Simulate OpenTUI sending a message to the CLI.

    Args:
        message: User message

    Returns:
        Response from the CLI
    """
    # Invoke the CLI as OpenTUI would
    result = subprocess.run(
        [sys.executable, "interview_cli.py", "--force-non-tty"],
        input=message,
        capture_output=True,
        text=True,
        cwd=os.path.dirname(__file__),
    )

    return result.stdout


def simulate_opentui_session():
    """Simulate a complete OpenTUI interview session."""

    print("=" * 60)
    print("OpenTUI Interview Simulation")
    print("=" * 60)
    print()

    # Clean up previous session
    import shutil
    from pathlib import Path
    sessions_dir = Path.home() / ".ralph" / "sessions"
    if sessions_dir.exists():
        shutil.rmtree(sessions_dir)

    messages = [
        "I want to build a REST API for a todo list application",
        "Python with FastAPI",
        "It should have user authentication, CRUD for todos, and priorities",
        "/status",
        "SQLAlchemy for the database, with PostgreSQL",
        # "/done" would complete the interview stage
    ]

    for i, msg in enumerate(messages, 1):
        print(f"[Message {i}]")
        print(f"User: {msg}")
        print()

        # Send message (simulates OpenTUI invocation)
        response = send_message(msg)

        print("Assistant:")
        print(response)
        print()
        print("-" * 60)
        print()

    print("=" * 60)
    print("Session Complete!")
    print("=" * 60)
    print()
    print("Key observations:")
    print("- Each message is a separate program invocation")
    print("- State persists across invocations via SessionManager")
    print("- No blocking loops - program exits after each message")
    print("- Interview context is maintained throughout")
    print()


if __name__ == "__main__":
    simulate_opentui_session()
