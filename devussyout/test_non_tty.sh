#!/bin/bash
# Test script for non-TTY mode

set -e

echo "========================================="
echo "Testing Non-TTY Interview Mode"
echo "========================================="
echo ""

# Clean up any existing session
echo "Cleaning up previous sessions..."
rm -f ~/.ralph/sessions/active_session.txt
rm -f ~/.ralph/sessions/session_*.json

echo ""
echo "Test 1: Create new session"
echo "========================================="
# Use python3 to ensure correct interpreter on systems without `python`
echo "I want to build a REST API for user management" | python3 interview_cli.py --force-non-tty --model opencode/claude-sonnet-4-5
echo ""

echo "Test 2: Resume session with follow-up"
echo "========================================="
echo "Python with FastAPI framework" | python3 interview_cli.py --force-non-tty --model opencode/claude-sonnet-4-5
echo ""

echo "Test 3: Check status"
echo "========================================="
echo "/status" | python3 interview_cli.py --force-non-tty --model opencode/claude-sonnet-4-5
echo ""

echo "Test 4: Get help"
echo "========================================="
echo "/help" | python3 interview_cli.py --force-non-tty --model opencode/claude-sonnet-4-5
echo ""

echo "Test 5: Continue interview"
echo "========================================="
echo "It should support JWT authentication and CRUD operations for user profiles" | python3 interview_cli.py --force-non-tty --model opencode/claude-sonnet-4-5
echo ""

echo "========================================="
echo "All tests completed!"
echo "========================================="
echo ""
echo "To clean up:"
echo "  rm -rf ~/.ralph/sessions/"
echo ""
echo "To continue the interview:"
echo "  echo 'your message' | python interview_cli.py"
echo ""
