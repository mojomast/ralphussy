#!/usr/bin/env node

/**
 * Ralph Slash Commands for OpenCode TUI
 * 
 * This script provides slash command completion for Ralph
 * Run this to get the slash command definitions
 */

const commands = [
  {
    command: '/ralph',
    description: 'Start Ralph autonomous loop',
    arguments: '<task description>',
    options: [
      { name: '--max-iterations', description: 'Maximum iterations (default: 100)' },
      { name: '--completion-promise', description: 'Completion signal (default: COMPLETE)' }
    ],
    examples: [
      '/ralph Build a REST API. Output <promise>COMPLETE</promise> when done.',
      '/ralph Write tests. --max-iterations 20',
      '/ralph Refactor auth module. --completion-promise DONE'
    ]
  },
  {
    command: '/ralph-status',
    alias: ['/ralphs', '/rs'],
    description: 'Check Ralph loop status'
  },
  {
    command: '/ralph-stop',
    alias: ['/ralphq', '/rq'],
    description: 'Stop running Ralph loop'
  },
  {
    command: '/ralph-context',
    alias: ['/ralphc', '/rc'],
    arguments: '<message>',
    description: 'Add context to next iteration',
    examples: [
      '/ralph-context Focus on the authentication module first',
      '/ralph-context Try using TypeScript instead of JavaScript'
    ]
  },
  {
    command: '/ralph-clear',
    alias: ['/ralphx', '/rx'],
    description: 'Clear pending context'
  },
  {
    command: '/ralph-help',
    alias: ['/ralphh', '/rh'],
    description: 'Show Ralph help'
  }
];

function generateBashCompletion() {
  console.log(`# Ralph Slash Commands - Bash Completion

_ralph_commands() {
    local commands="ralph ralph-status ralph-stop ralph-context ralph-clear ralph-help"
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
}

_ralph_completion() {
    local cur prev words cword
    _init_completion || return
    
    # Main commands
    if [[ "$cur" == /* ]]; then
        COMPREPLY=( $(compgen -W "/ralph /ralph-status /ralph-stop /ralph-context /ralph-clear /ralph-help" -- "$cur") )
        return
    fi
    
    # Sub-command completion
    case "$prev" in
        /ralph|/ralph-context)
            return
            ;;
        /ralph-status|/ralph-stop|/ralph-clear|/ralph-help)
            return
            ;;
    esac
    
    _ralph_commands
}
complete -F _ralph_completion ralph`);
}

function generateZshCompletion() {
  console.log(`#compdef ralph

_ralph_commands=(
  '/ralph:Start autonomous loop'
  '/ralph-status:Check Ralph loop status'
  '/ralph-stop:Stop running Ralph loop'
  '/ralph-context:Add context to next iteration'
  '/ralph-clear:Clear pending context'
  '/ralph-help:Show Ralph help'
)

_ralph() {
    local -a commands
    commands=($_ralph_commands)
    
    if (( CURRENT == 2 )); then
        _describe 'ralph commands' commands
        return
    fi
    
    case "$words[2]" in
        /ralph)
            _message "Enter task description"
            ;;
        /ralph-context)
            _message "Enter context message"
            ;;
    esac
}

compdef _ralph ralph`);
}

function printCommands() {
  console.log('Ralph Slash Commands for OpenCode\n');
  console.log('═'.repeat(60));
  console.log('');
  
  for (const cmd of commands) {
    console.log(`${cmd.command}`);
    if (cmd.alias) {
      console.log(`   Aliases: ${cmd.alias.join(', ')}`);
    }
    console.log(`   ${cmd.description}`);
    
    if (cmd.arguments) {
      console.log(`   Args: ${cmd.arguments}`);
    }
    
    if (cmd.examples) {
      console.log('');
      console.log('   Examples:');
      for (const example of cmd.examples) {
        console.log(`     ${example}`);
      }
    }
    
    console.log('');
    console.log('─'.repeat(60));
    console.log('');
  }
}

function generateOpencodeConfig() {
  console.log(`{
  "agents": {
    "ralph": {
      "name": "Ralph",
      "description": "Autonomous loop agent - iterates until task completion",
      "slashCommands": [
        {
          "command": "/ralph",
          "description": "Start autonomous loop",
          "arguments": "<task description>",
          "options": [
            { "name": "--max-iterations", "description": "Maximum iterations" },
            { "name": "--completion-promise", "description": "Completion signal" }
          ]
        },
        {
          "command": "/ralph-status",
          "description": "Check loop status"
        },
        {
          "command": "/ralph-stop",
          "description": "Stop loop"
        },
        {
          "command": "/ralph-context",
          "description": "Add context",
          "arguments": "<message>"
        },
        {
          "command": "/ralph-clear",
          "description": "Clear context"
        },
        {
          "command": "/ralph-help",
          "description": "Show help"
        }
      ]
    }
  }
}`);
}

// Main
const args = process.argv.slice(2);
const format = args[0] || 'text';

switch (format) {
  case '--bash':
    generateBashCompletion();
    break;
  case '--zsh':
    generateZshCompletion();
    break;
  case '--config':
    generateOpencodeConfig();
    break;
  case '--json':
    console.log(JSON.stringify(commands, null, 2));
    break;
  default:
    printCommands();
}