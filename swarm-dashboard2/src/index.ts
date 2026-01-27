#!/usr/bin/env node

import React from 'react';
import { createRoot, useKeyboard, useRenderer } from '@opentui/react';
import { createCliRenderer, ConsolePosition, RGBA, t, bold, fg, bg, underline } from '@opentui/core';
import fs from 'fs';
import os from 'os';
import path from 'path';

// ============================================================================
// MODERN COLOR SCHEME (GitHub Dark inspired)
// ============================================================================
const COLORS = {
  // Backgrounds
  background: '#0d1117',
  surface: '#161b22',
  surfaceHover: '#21262d',
  surfaceActive: '#30363d',
  
  // Borders
  border: '#30363d',
  borderFocus: '#58a6ff',
  borderSuccess: '#3fb950',
  borderWarning: '#d29922',
  borderError: '#f85149',
  
  // Text
  text: '#c9d1d9',
  textMuted: '#8b949e',
  textBright: '#ffffff',
  
  // Accent colors
  accent: '#58a6ff',
  accentHover: '#79b8ff',
  
  // Status colors
  success: '#3fb950',
  successDim: '#238636',
  warning: '#d29922',
  warningDim: '#9e6a03',
  error: '#f85149',
  errorDim: '#da3633',
  info: '#58a6ff',
  infoDim: '#1f6feb',
  
  // Special
  purple: '#a855f7',
  purpleDim: '#7c3aed',
  pink: '#f472b6',
  cyan: '#22d3ee',
  orange: '#f97316',
};

// ASCII Art title for RALPH
const RALPH_ASCII_TITLE = `
██████╗  █████╗ ██╗     ██████╗ ██╗  ██╗
██╔══██╗██╔══██╗██║     ██╔══██╗██║  ██║
██████╔╝███████║██║     ██████╔╝███████║
██╔══██╗██╔══██║██║     ██╔═══╝ ██╔══██║
██║  ██║██║  ██║███████╗██║     ██║  ██║
╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝
`.trim();

// Smaller ASCII for constrained terminals
const RALPH_ASCII_SMALL = `╔═══╗ RALPH LIVE ╔═══╗`;

// Animated spinner frames
const SPINNER_FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
const PROGRESS_CHARS = ['▏', '▎', '▍', '▌', '▋', '▊', '▉', '█'];

// Debug logging helper - writes to ~/.ralph/dashboard-ui.log
const DEBUG_LOG_PATH = path.join(os.homedir(), '.ralph', 'dashboard-ui.log');
const CONFIG_PATH = path.join(os.homedir(), '.ralph', 'config.json');

// ============================================================================
// CONFIG TYPES AND DEFAULTS
// ============================================================================

interface ProviderModel {
  provider: string;  // e.g., 'openai', 'anthropic', 'openrouter', 'ollama'
  model: string;     // e.g., 'gpt-4o', 'claude-sonnet-4-20250514', 'deepseek/deepseek-chat'
}

interface DevPlanModels {
  interview: ProviderModel;
  design: ProviderModel;
  devplan: ProviderModel;
  phase: ProviderModel;
  handoff: ProviderModel;
}

interface RalphConfig {
  // Mode: which system to use
  mode: 'ralph' | 'devplan' | 'swarm';
  
  // Provider/Model settings
  swarmModel: ProviderModel;
  ralphModel: ProviderModel;
  devplanModels: DevPlanModels;
  
  // Swarm settings
  swarmAgentCount: number;
  
  // Timeouts (in seconds)
  commandTimeout: number;
  llmTimeout: number;
  pollInterval: number;
  
  // Behavioral settings
  autoRefresh: boolean;
  showCosts: boolean;
  maxLogLines: number;
  debugMode: boolean;
}

const DEFAULT_PROVIDER_MODEL: ProviderModel = {
  provider: 'anthropic',
  model: 'claude-sonnet-4-20250514',
};

const DEFAULT_CONFIG: RalphConfig = {
  mode: 'swarm',
  swarmModel: { ...DEFAULT_PROVIDER_MODEL },
  ralphModel: { ...DEFAULT_PROVIDER_MODEL },
  devplanModels: {
    interview: { provider: 'anthropic', model: 'claude-sonnet-4-20250514' },
    design: { provider: 'anthropic', model: 'claude-sonnet-4-20250514' },
    devplan: { provider: 'anthropic', model: 'claude-sonnet-4-20250514' },
    phase: { provider: 'anthropic', model: 'claude-sonnet-4-20250514' },
    handoff: { provider: 'anthropic', model: 'claude-sonnet-4-20250514' },
  },
  swarmAgentCount: 4,
  commandTimeout: 300,
  llmTimeout: 120,
  pollInterval: 5,
  autoRefresh: true,
  showCosts: true,
  maxLogLines: 200,
  debugMode: false,
};

// Fallback providers and models (used if opencode models fails)
const FALLBACK_PROVIDERS: Record<string, string[]> = {
  'anthropic': ['claude-sonnet-4-20250514', 'claude-opus-4-20250514', 'claude-3-5-haiku-20241022'],
  'openai': ['gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo', 'o1', 'o1-mini', 'o3-mini'],
  'openrouter': ['deepseek/deepseek-chat', 'deepseek/deepseek-reasoner', 'google/gemini-2.0-flash-001', 'meta-llama/llama-3.3-70b-instruct'],
  'ollama': ['llama3.2', 'qwen2.5-coder', 'deepseek-r1:14b', 'codellama'],
};

// Fetch available models from OpenCode CLI
// Returns a map of provider -> model names
function fetchOpenCodeModels(): Record<string, string[]> {
  try {
    const { execSync } = require('child_process');
    // Redirect stderr to /dev/null to avoid INFO messages polluting output
    const output = execSync('opencode models 2>/dev/null', { encoding: 'utf8', timeout: 10000, shell: true });
    const lines = output.split('\n').filter((line: string) => line.trim());
    
    const providers: Record<string, string[]> = {};
    
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      // Skip any lines that look like log messages
      if (trimmed.startsWith('INFO') || trimmed.startsWith('WARN') || trimmed.startsWith('ERROR')) continue;
      
      // Models are in format "provider/model"
      if (trimmed.includes('/')) {
        const [provider, ...modelParts] = trimmed.split('/');
        const model = modelParts.join('/'); // Handle cases like "deepseek/deepseek-chat"
        if (provider && model) {
          if (!providers[provider]) {
            providers[provider] = [];
          }
          // Store full model identifier for this provider
          if (!providers[provider].includes(trimmed)) {
            providers[provider].push(trimmed);
          }
        }
      } else {
        // Models without provider prefix go under 'default' provider
        if (!providers['default']) {
          providers['default'] = [];
        }
        if (!providers['default'].includes(trimmed)) {
          providers['default'].push(trimmed);
        }
      }
    }
    
    // If we got models, return them
    if (Object.keys(providers).length > 0) {
      debugLog(`Fetched ${Object.keys(providers).length} providers from opencode models`);
      return providers;
    }
  } catch (e) {
    debugLog(`Failed to fetch opencode models: ${e}`);
  }
  
  // Return fallback if fetch failed
  return { ...FALLBACK_PROVIDERS };
}

// Cached providers - will be populated on startup
let cachedProviders: Record<string, string[]> = { ...FALLBACK_PROVIDERS };

// Alias for backwards compatibility
const PROVIDERS = cachedProviders;

function loadConfig(): RalphConfig {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const data = fs.readFileSync(CONFIG_PATH, 'utf8');
      const loaded = JSON.parse(data);
      // Merge with defaults to ensure all fields exist
      return { ...DEFAULT_CONFIG, ...loaded };
    }
  } catch (e) {
    debugLog(`Failed to load config: ${e}`);
  }
  return { ...DEFAULT_CONFIG };
}

function saveConfig(config: RalphConfig): boolean {
  try {
    const dir = path.dirname(CONFIG_PATH);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
    return true;
  } catch (e) {
    debugLog(`Failed to save config: ${e}`);
    return false;
  }
}
function debugLog(message: string): void {
  try {
    const timestamp = new Date().toISOString();
    const logLine = `[${timestamp}] ${message}\n`;
    // Ensure directory exists
    const logDir = path.dirname(DEBUG_LOG_PATH);
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }
    fs.appendFileSync(DEBUG_LOG_PATH, logLine);
  } catch (e) {
    // Silently fail if logging fails
  }
}

// Type definitions for detail view
type DetailViewType = { type: 'task'; data: any } | { type: 'worker'; data: any } | null;
type PaneType = 'actions' | 'tasks' | 'workers' | 'console' | 'ralph';

// Focus colors for visual indicator - using new color scheme
const FOCUS_COLORS = {
  focused: { border: COLORS.borderFocus, title: COLORS.borderFocus, bg: COLORS.background },
  unfocused: { border: COLORS.border, title: COLORS.textMuted, bg: COLORS.surface },
};

// Hover state tracker - track what element mouse is over
type HoverableElement = 'none' | 'tasks' | 'workers' | 'actions' | 'ralph' | 'options-btn' | 'help-btn';


async function main() {
  try {
    console.error('Starting swarm-dashboard2 (React + OpenTUI)...');

    const renderer = await createCliRenderer({
      consoleOptions: {
        position: ConsolePosition.BOTTOM,
        sizePercent: 20,
      },
      exitOnCtrlC: false,
      useMouse: true,           // BRRRRR - Mouse support enabled!
      enableMouseMovement: true, // Track mouse movement for hover states
      useAlternateScreen: true,
    });

    // Create the React root for this renderer
    const root = createRoot(renderer);

    // Load DB helper from original dashboard compiled dist
    const dbMod = await import('../../swarm-dashboard/dist/database-bun.js');
    const db = dbMod.createSwarmDatabase();

    function App() {
      const [run, setRun] = React.useState<any | null>(null);
      const [workers, setWorkers] = React.useState<any[]>([]);
      const [tasks, setTasks] = React.useState<any[]>([]);
      const [logs, setLogs] = React.useState<any[]>([]);
      const [costs, setCosts] = React.useState<any>({ total_cost: 0, total_prompt_tokens: 0, total_completion_tokens: 0 });
      const [stats, setStats] = React.useState<any>({ pending: 0, in_progress: 0, completed: 0, failed: 0 });
      const [recentCosts, setRecentCosts] = React.useState<any[]>([]);
      const [ralphLines, setRalphLines] = React.useState<string[]>([]);
      const [focusedPane, setFocusedPane] = React.useState<PaneType>('tasks');
      
      // BRRRRR - Mouse hover state tracking
      const [hoveredElement, setHoveredElement] = React.useState<HoverableElement>('none');
      const [showHelp, setShowHelp] = React.useState(false);
      
      // Animated spinner for loading states
      const [spinnerFrame, setSpinnerFrame] = React.useState(0);
      
      // Selected item index per pane for detail view navigation
      const [selectedIndex, setSelectedIndex] = React.useState<Record<PaneType, number>>({
        actions: 0, tasks: 0, workers: 0, console: 0, ralph: 0
      });
      
      // Detail view overlay state
      const [detailView, setDetailView] = React.useState<DetailViewType>(null);
      
      // Persistent scroll offsets per pane
      const scrollOffsetsRef = React.useRef<Record<PaneType, number>>({
        actions: 0, tasks: 0, workers: 0, console: 0, ralph: 0
      });
      
       // Animate spinner
      React.useEffect(() => {
        const interval = setInterval(() => {
          setSpinnerFrame(prev => (prev + 1) % SPINNER_FRAMES.length);
        }, 100);
        return () => clearInterval(interval);
      }, []);

      // Page size used for visible window when computing auto-scroll behavior
      const PAGE_SIZE = 15;
      
      // Global scroll offset for scrolling through entire dashboard
      const [globalScrollOffset, setGlobalScrollOffset] = React.useState(0);

      const renderer = useRenderer();
      
      // Helper to get items for current pane
      const getItemsForPane = (pane: PaneType): any[] => {
        switch (pane) {
          case 'tasks': return tasks;
          case 'workers': return workers;
          case 'actions': return logs;
          case 'console': return logs;
          case 'ralph': return ralphLines;
          default: return [];
        }
      };

      // keyboard handling for pane focus, scrolling, and detail view
      // Throttle repeated key events to avoid frequent rerenders
      let lastKeyAt = 0;
      const KEY_THROTTLE_MS = 80;
      // Command modal state for confirmations/inputs/output streaming
      const [commandModal, setCommandModal] = React.useState<any>(null);
      // Input buffer for text input modals
      const [inputBuffer, setInputBuffer] = React.useState<Record<string, string>>({});
      // Selected task filter for Ralph Live (null => show all)
      const [selectedTaskId, setSelectedTaskId] = React.useState<number | null>(null);
      const selectedTaskIdRef = React.useRef<number | null>(null);
      const applySelectedTaskId = (id: number | null) => { selectedTaskIdRef.current = id; setSelectedTaskId(id); };
      // Selected run filter (null => show current run)
      const [selectedRunId, setSelectedRunId] = React.useState<string | null>(null);
      const selectedRunIdRef = React.useRef<string | null>(null);
      const applySelectedRunId = (id: string | null) => { selectedRunIdRef.current = id; setSelectedRunId(id); };

      // Devplan generation pipeline state
      type DevplanStage = 'idle' | 'interview' | 'design' | 'devplan' | 'phases' | 'handoff' | 'complete' | 'error';
      const [devplanStage, setDevplanStage] = React.useState<DevplanStage>('idle');
      const [devplanProgress, setDevplanProgress] = React.useState<{
        stage: DevplanStage;
        message: string;
        progress: number; // 0-100
        error?: string;
        outputPath?: string;
      }>({ stage: 'idle', message: '', progress: 0 });
      const devplanProcessRef = React.useRef<any>(null);

      // Configuration state - loaded from ~/.ralph/config.json
      const [config, setConfig] = React.useState<RalphConfig>(() => loadConfig());
      
      // Options menu state
      type OptionsSection = 'mode' | 'swarm' | 'ralph' | 'devplan' | 'settings';
      const [optionsSection, setOptionsSection] = React.useState<OptionsSection>('mode');
      const [optionsFocusedField, setOptionsFocusedField] = React.useState(0);
      
      // OpenCode models state - fetched from opencode CLI
      const [openCodeModels, setOpenCodeModels] = React.useState<Record<string, string[]>>(() => {
        // Initialize by fetching from opencode CLI
        const models = fetchOpenCodeModels();
        cachedProviders = models; // Update global cache
        return models;
      });
      
      // Selected provider for model selection (used in options modal)
      const [selectedProvider, setSelectedProvider] = React.useState<string>(() => {
        const providers = Object.keys(openCodeModels);
        return providers.length > 0 ? providers[0] : 'anthropic';
      });
      
      // Helper to get providers list
      const getProviders = (): string[] => Object.keys(openCodeModels);
      
      // Helper to get models for a provider
      const getModelsForProvider = (provider: string): string[] => {
        return openCodeModels[provider] || [];
      };
      
      // Refresh OpenCode models (can be called to reload)
      const refreshOpenCodeModels = () => {
        const models = fetchOpenCodeModels();
        setOpenCodeModels(models);
        cachedProviders = models;
        appendRalphLines(`[CONFIG] Refreshed models: ${Object.keys(models).length} providers`);
      };
      
      // Helper to update and save config
      const updateConfig = (updates: Partial<RalphConfig>) => {
        setConfig(prev => {
          const newConfig = { ...prev, ...updates };
          saveConfig(newConfig);
          appendRalphLines('[CONFIG] Settings saved');
          return newConfig;
        });
      };
      
      // Helper to update nested devplan models
      const updateDevplanModel = (stage: keyof DevPlanModels, updates: Partial<ProviderModel>) => {
        setConfig(prev => {
          const newConfig = {
            ...prev,
            devplanModels: {
              ...prev.devplanModels,
              [stage]: { ...prev.devplanModels[stage], ...updates }
            }
          };
          saveConfig(newConfig);
          return newConfig;
        });
      };

      // Refs used by DB polling so other helpers can trigger a load
      const snapshotRef = React.useRef<any>(null);
      const lastDbMtimeRef = React.useRef<number>(0);
      const pollCounterRef = React.useRef<number>(0);
      const mountedRef = React.useRef<boolean>(true);

      // Helper to append to Ralph Live lines and keep a bounded history
      const appendRalphLines = (lines: string[] | string) => {
        setRalphLines(prev => {
          const add = Array.isArray(lines) ? lines : [lines];
          const merged = [...prev, ...add];
          // keep last N lines based on config
          return merged.slice(-config.maxLogLines);
        });
      };

      // Command rate-limiting (ms)
      const CMD_RATE_MS = 5000;
      const lastCommandTimeRef = React.useRef<Record<string, number>>({});

      // Helper to spawn commands and stream stdout/stderr into Ralph Live
      // options: { showOutput:boolean, title?:string, key?:string }
      const runCommandStream = (cmd: string, args: string[] = [], opts: any = {}) => {
        const key = opts.key || `${cmd} ${args.join(' ')}`;
        const now = Date.now();
        const last = lastCommandTimeRef.current[key] || 0;
        if (now - last < CMD_RATE_MS) {
          appendRalphLines(`[UI] Command blocked: please wait ${Math.ceil((CMD_RATE_MS - (now - last))/1000)}s`);
          return null;
        }
        lastCommandTimeRef.current[key] = now;

        try {
          const { spawn } = require('child_process');
          const child = spawn(cmd, args, { env: process.env });
          appendRalphLines([`--- Running: ${cmd} ${args.join(' ')} ---`]);
          // Optionally show an output overlay while the command runs
          if (opts.showOutput) {
            setCommandModal({ type: 'output', title: opts.title || `Running: ${args.join(' ')}`, startAt: (ralphLines || []).length });
          }
          child.stdout.on('data', (chunk: Buffer) => {
            const text = chunk.toString();
            text.split(/\r?\n/).forEach((ln: string) => { if (ln.trim().length) appendRalphLines(ln); });
          });
          child.stderr.on('data', (chunk: Buffer) => {
            const text = chunk.toString();
            text.split(/\r?\n/).forEach((ln: string) => { if (ln.trim().length) appendRalphLines(`[ERR] ${ln}`); });
          });
          child.on('close', (code: number) => {
            appendRalphLines(`--- Exit code: ${code} ---`);
            // trigger immediate DB reload after command finishes
            lastDbMtimeRef.current = 0;
            // hide output overlay shortly after completion
            setTimeout(() => {
              try { if (commandModal && commandModal.type === 'output') setCommandModal(null); } catch (e) {}
            }, 800);
            // schedule an immediate reload
            setTimeout(() => {
              try { load(); } catch (e) { /* load is hoisted */ }
            }, 300);
          });
          return child;
        } catch (err) {
          appendRalphLines(`[ERR] Failed to spawn ${cmd}: ${String(err)}`);
          return null;
        }
      };
      const ralphCli = `${process.cwd()}/ralph-refactor/ralph-swarm`;

      // Devplan pipeline runner - spawns Python pipeline and tracks progress
      const runDevplanPipeline = (interviewData: any) => {
        const { project_name, languages, frameworks, apis, requirements } = interviewData;
        
        setDevplanStage('design');
        setDevplanProgress({ stage: 'design', message: 'Generating project design...', progress: 10 });
        appendRalphLines('[DEVPLAN] Starting pipeline: design → devplan → phases → handoff');
        appendRalphLines(`[DEVPLAN] Project: ${project_name}`);
        
        // Open the progress modal to show pipeline status
        setCommandModal({
          type: 'devplan-progress',
          title: 'DevPlan Generation Progress',
        });
        
        // Build the pipeline runner script inline
        const pipelineScript = `
import asyncio
import sys
import os
import json

# Add devussyout to path
sys.path.insert(0, '${process.cwd()}/devussyout/src')
sys.path.insert(0, '${process.cwd()}/devussyout/src/pipeline')

from pipeline.project_design import ProjectDesignGenerator
from pipeline.basic_devplan import BasicDevPlanGenerator
from pipeline.detailed_devplan import DetailedDevPlanGenerator
from pipeline.handoff_prompt import HandoffPromptGenerator
from concurrency import ConcurrencyManager
from llm_client import LLMClient

class SimpleLLMClient(LLMClient):
    def __init__(self):
        class Config:
            max_concurrent_requests = 3
            streaming_enabled = False
        self._config = Config()
    
    async def generate_completion(self, prompt, **kwargs):
        # Use opencode CLI for LLM calls
        import subprocess
        result = subprocess.run(
            ['opencode', 'ask', '-p', prompt[:4000]],
            capture_output=True, text=True, timeout=300
        )
        return result.stdout if result.returncode == 0 else f"Error: {result.stderr}"

async def run_pipeline():
    project_name = ${JSON.stringify(project_name)}
    languages = ${JSON.stringify(languages.split(',').map((s: string) => s.trim()).filter((s: string) => s))}
    frameworks = ${JSON.stringify((frameworks || '').split(',').map((s: string) => s.trim()).filter((s: string) => s))}
    apis = ${JSON.stringify((apis || '').split(',').map((s: string) => s.trim()).filter((s: string) => s))}
    requirements = ${JSON.stringify(requirements)}
    
    llm = SimpleLLMClient()
    
    # Stage 1: Design
    print(json.dumps({"stage": "design", "progress": 15, "message": "Generating project design..."}), flush=True)
    pdg = ProjectDesignGenerator(llm)
    design = await pdg.generate(project_name, languages, requirements, frameworks=frameworks, apis=apis)
    print(json.dumps({"stage": "design", "progress": 25, "message": "Project design complete"}), flush=True)
    
    # Stage 2: Basic DevPlan
    print(json.dumps({"stage": "devplan", "progress": 35, "message": "Generating basic devplan..."}), flush=True)
    bdg = BasicDevPlanGenerator(llm)
    basic_plan = await bdg.generate(design)
    print(json.dumps({"stage": "devplan", "progress": 50, "message": f"Basic devplan: {len(basic_plan.phases)} phases"}), flush=True)
    
    # Stage 3: Detailed Phases
    print(json.dumps({"stage": "phases", "progress": 55, "message": "Generating detailed phases..."}), flush=True)
    class SimpleConfig:
        max_concurrent_requests = 2
    cm = ConcurrencyManager(config=SimpleConfig())
    ddg = DetailedDevPlanGenerator(llm, cm)
    
    def on_phase_complete(result):
        pct = 55 + int((result.phase.number / len(basic_plan.phases)) * 25)
        print(json.dumps({"stage": "phases", "progress": pct, "message": f"Phase {result.phase.number} detailed"}), flush=True)
    
    detailed_plan = await ddg.generate(basic_plan, project_name, tech_stack=design.tech_stack, on_phase_complete=on_phase_complete)
    print(json.dumps({"stage": "phases", "progress": 80, "message": "All phases detailed"}), flush=True)
    
    # Stage 4: Handoff
    print(json.dumps({"stage": "handoff", "progress": 85, "message": "Generating handoff prompt..."}), flush=True)
    hpg = HandoffPromptGenerator()
    handoff = hpg.generate(detailed_plan, project_name)
    print(json.dumps({"stage": "handoff", "progress": 95, "message": "Handoff generated"}), flush=True)
    
    # Save outputs
    output_dir = os.path.expanduser(f"~/.ralph/devplans/{project_name}")
    os.makedirs(output_dir, exist_ok=True)
    
    with open(f"{output_dir}/design.md", "w") as f:
        f.write(design.raw_llm_response or str(design))
    
    with open(f"{output_dir}/devplan.md", "w") as f:
        # Format as markdown
        content = f"# DevPlan: {project_name}\\n\\n"
        for phase in detailed_plan.phases:
            content += f"## Phase {phase.number}: {phase.title}\\n\\n"
            for step in phase.steps:
                content += f"- [ ] {step.number}: {step.description}\\n"
            content += "\\n"
        f.write(content)
    
    with open(f"{output_dir}/handoff.md", "w") as f:
        f.write(handoff.content)
    
    print(json.dumps({"stage": "complete", "progress": 100, "message": "Pipeline complete!", "outputPath": output_dir}), flush=True)

asyncio.run(run_pipeline())
`;
        
        try {
          const { spawn } = require('child_process');
          const child = spawn('python3', ['-c', pipelineScript], { 
            env: { ...process.env, PYTHONUNBUFFERED: '1' },
            cwd: process.cwd()
          });
          devplanProcessRef.current = child;
          
          child.stdout.on('data', (chunk: Buffer) => {
            const lines = chunk.toString().split('\n').filter((l: string) => l.trim());
            for (const line of lines) {
              try {
                const data = JSON.parse(line);
                if (data.stage) {
                  setDevplanStage(data.stage as DevplanStage);
                  setDevplanProgress({
                    stage: data.stage,
                    message: data.message || '',
                    progress: data.progress || 0,
                    outputPath: data.outputPath,
                  });
                  appendRalphLines(`[DEVPLAN] ${data.message}`);
                }
              } catch (e) {
                // Not JSON, just log it
                appendRalphLines(`[DEVPLAN] ${line}`);
              }
            }
          });
          
          child.stderr.on('data', (chunk: Buffer) => {
            const text = chunk.toString();
            appendRalphLines(`[DEVPLAN ERR] ${text.split('\n')[0]}`);
          });
          
          child.on('close', (code: number) => {
            devplanProcessRef.current = null;
            if (code === 0) {
              appendRalphLines('[DEVPLAN] Pipeline completed successfully!');
              setDevplanStage('complete');
            } else {
              appendRalphLines(`[DEVPLAN] Pipeline failed with exit code ${code}`);
              setDevplanStage('error');
              setDevplanProgress(prev => ({ ...prev, stage: 'error', error: `Exit code: ${code}` }));
            }
          });
          
          child.on('error', (err: Error) => {
            appendRalphLines(`[DEVPLAN ERR] Failed to start pipeline: ${err.message}`);
            setDevplanStage('error');
            setDevplanProgress({ stage: 'error', message: 'Failed to start', progress: 0, error: err.message });
          });
          
        } catch (err) {
          appendRalphLines(`[DEVPLAN ERR] ${String(err)}`);
          setDevplanStage('error');
        }
      };
      useKeyboard((key) => {
        try {
          const now = Date.now();
          if (now - lastKeyAt < KEY_THROTTLE_MS) return;
          lastKeyAt = now;
          // If a command modal is active, handle only modal keys
          if (commandModal) {
            const k = key.name || '';
            if (commandModal.type === 'confirm') {
              if (k === 'y' || k === 'return') {
                try { commandModal.onConfirm && commandModal.onConfirm(); } catch (e) {}
                setCommandModal(null);
              } else if (k === 'n' || k === 'escape') {
                try { commandModal.onCancel && commandModal.onCancel(); } catch (e) {}
                setCommandModal(null);
              }
              return;
            } else if (commandModal.type === 'output') {
              // allow closing output overlay with ESC or q
              if ((key.name === 'escape') || (key.name === 'q')) {
                setCommandModal(null);
              }
              return;
            } else if (commandModal.type === 'select-task') {
              // navigate selection with up/down, confirm with return, cancel with escape
              if (k === 'up') {
                setCommandModal((cm: any) => ({ ...cm, sel: Math.max(0, (cm.sel || 0) - 1) }));
                return;
              } else if (k === 'down') {
                setCommandModal((cm: any) => ({ ...cm, sel: Math.min(((cm.options || []).length - 1) || 0, (cm.sel || 0) + 1) }));
                return;
              } else if (k === 'return') {
                try {
                  const idx = commandModal.sel || 0;
                  const task = (commandModal.options || [])[idx];
                  if (task) {
                    setSelectedTaskId(task.id || null);
                    selectedTaskIdRef.current = task.id || null;
                    appendRalphLines(`[UI] Ralph Live filtered to task ${task.id}`);
                  }
                } catch (e) {}
                setCommandModal(null);
                return;
              } else if (k === 'escape' || k === 'q') {
                setCommandModal(null);
                return;
              }
            } else if (commandModal.type === 'select-run') {
               // navigate selection with up/down, confirm with return, cancel with escape
               if (k === 'up') {
                 setCommandModal((cm: any) => ({ ...cm, sel: Math.max(0, (cm.sel || 0) - 1) }));
                 return;
               } else if (k === 'down') {
                 setCommandModal((cm: any) => ({ ...cm, sel: Math.min(((cm.options || []).length - 1) || 0, (cm.sel || 0) + 1) }));
                 return;
               } else if (k === 'return') {
                 try {
                   const idx = commandModal.sel || 0;
                   const item = (commandModal.options || [])[idx];
                   if (item) {
                     // Apply selected run id (null means current)
                     applySelectedRunId(item.run_id || null);
                     selectedRunIdRef.current = item.run_id || null;
                     // Provide immediate UI feedback and trigger reload
                     try {
                       if (item.run_id) {
                         // try to lookup run details for a helpful message
                         const info = (typeof db.getRunById === 'function') ? db.getRunById(item.run_id) : null;
                         if (info) {
                           appendRalphLines(`[UI] Showing run ${info.run_id} status=${(info.status||'').toUpperCase()}`);
                           if ((info.status||'') !== 'running') appendRalphLines('[UI] NOTE: Viewing historical run — updates may be stale');
                         } else {
                           appendRalphLines(`[UI] Showing run: ${item.run_id}`);
                         }
                       } else {
                         appendRalphLines('[UI] Showing current run');
                       }
                     } catch (e) {
                       appendRalphLines(`[UI] Showing run: ${item.run_id || '(current)'} `);
                     }
                     // force immediate reload and schedule load shortly after modal closes
                     lastDbMtimeRef.current = 0;
                     setTimeout(() => { try { load(); } catch (e) {} }, 120);
                   }
                 } catch (e) {}
                 setCommandModal(null);
                 return;
               } else if (k === 'escape' || k === 'q') {
                 setCommandModal(null);
                 return;
               }
            } else if (commandModal.type === 'start-config') {
              // Input modal for start configuration - navigate fields and type text
              const fields = commandModal.fields || [];
              const focusedField = commandModal.focusedField || 0;
              const currentField = fields[focusedField];
              
              if (k === 'escape') {
                debugLog('Start-config cancelled');
                try { commandModal.onCancel && commandModal.onCancel(); } catch (e) {}
                setCommandModal(null);
                setInputBuffer({});
                return;
              } else if (k === 'tab' || k === 'down') {
                // Move to next field
                const nextField = (focusedField + 1) % fields.length;
                setCommandModal((cm: any) => ({ ...cm, focusedField: nextField }));
                return;
              } else if (k === 'up') {
                // Move to previous field
                const prevField = (focusedField - 1 + fields.length) % fields.length;
                setCommandModal((cm: any) => ({ ...cm, focusedField: prevField }));
                return;
              } else if (k === 'return') {
                // Confirm - validate and call onConfirm
                const values: Record<string, string> = {};
                let valid = true;
                for (const field of fields) {
                  const val = inputBuffer[field.key] ?? field.value ?? '';
                  values[field.key] = val;
                  if (field.required && !val.trim()) {
                    appendRalphLines(`[ERR] ${field.label} is required`);
                    valid = false;
                  }
                }
                if (valid) {
                  try { commandModal.onConfirm && commandModal.onConfirm(values); } catch (e) {}
                  setCommandModal(null);
                  setInputBuffer({});
                }
                return;
              } else if (k === 'backspace') {
                // Delete last character from current field
                if (currentField) {
                  const currentVal = inputBuffer[currentField.key] ?? currentField.value ?? '';
                  const newVal = currentVal.slice(0, -1);
                  setInputBuffer((prev: any) => ({ ...prev, [currentField.key]: newVal }));
                }
                return;
              } else if (key.sequence && key.sequence.length === 1 && !key.ctrl && !key.meta) {
                // Type character into current field
                if (currentField) {
                  const currentVal = inputBuffer[currentField.key] ?? currentField.value ?? '';
                  const newVal = currentVal + key.sequence;
                  setInputBuffer((prev: any) => ({ ...prev, [currentField.key]: newVal }));
                }
                return;
              }
            } else if (commandModal.type === 'devplan-interview') {
              // Devplan interview modal - multi-field input for project interview
              const fields = commandModal.fields || [];
              const focusedField = commandModal.focusedField || 0;
              const currentField = fields[focusedField];
              
              if (k === 'escape') {
                debugLog('Devplan interview cancelled');
                try { commandModal.onCancel && commandModal.onCancel(); } catch (e) {}
                setCommandModal(null);
                setInputBuffer({});
                return;
              } else if (k === 'tab' || (k === 'down' && !currentField?.multiline)) {
                // Move to next field
                const nextField = (focusedField + 1) % fields.length;
                setCommandModal((cm: any) => ({ ...cm, focusedField: nextField }));
                return;
              } else if (k === 'up' && !currentField?.multiline) {
                // Move to previous field
                const prevField = (focusedField - 1 + fields.length) % fields.length;
                setCommandModal((cm: any) => ({ ...cm, focusedField: prevField }));
                return;
              } else if (k === 'return') {
                // For multiline fields, add newline; otherwise confirm if on last field
                if (currentField?.multiline) {
                  const currentVal = inputBuffer[currentField.key] ?? currentField.value ?? '';
                  const newVal = currentVal + '\n';
                  setInputBuffer((prev: any) => ({ ...prev, [currentField.key]: newVal }));
                  return;
                }
                // If on last field or Ctrl+Enter, confirm
                if (focusedField === fields.length - 1 || key.ctrl) {
                  const values: Record<string, string> = {};
                  let valid = true;
                  for (const field of fields) {
                    const val = inputBuffer[field.key] ?? field.value ?? '';
                    values[field.key] = val;
                    if (field.required && !val.trim()) {
                      appendRalphLines(`[ERR] ${field.label} is required`);
                      valid = false;
                    }
                  }
                  if (valid) {
                    debugLog(`Devplan interview submitted: ${JSON.stringify(values)}`);
                    try { commandModal.onConfirm && commandModal.onConfirm(values); } catch (e) {}
                    setCommandModal(null);
                    setInputBuffer({});
                  }
                } else {
                  // Move to next field
                  const nextField = (focusedField + 1) % fields.length;
                  setCommandModal((cm: any) => ({ ...cm, focusedField: nextField }));
                }
                return;
              } else if (k === 'backspace') {
                // Delete last character from current field
                if (currentField) {
                  const currentVal = inputBuffer[currentField.key] ?? currentField.value ?? '';
                  const newVal = currentVal.slice(0, -1);
                  setInputBuffer((prev: any) => ({ ...prev, [currentField.key]: newVal }));
                }
                return;
              } else if (key.sequence && key.sequence.length === 1 && !key.ctrl && !key.meta) {
                // Type character into current field
                if (currentField) {
                  const currentVal = inputBuffer[currentField.key] ?? currentField.value ?? '';
                  const newVal = currentVal + key.sequence;
                  setInputBuffer((prev: any) => ({ ...prev, [currentField.key]: newVal }));
                }
                return;
              }
            } else if (commandModal.type === 'devplan-progress') {
              // Devplan progress modal - just allow closing with ESC
              if (k === 'escape' || k === 'q') {
                // Cancel running pipeline if any
                if (devplanProcessRef.current) {
                  try { devplanProcessRef.current.kill(); } catch (e) {}
                  devplanProcessRef.current = null;
                }
                setCommandModal(null);
                setDevplanStage('idle');
                return;
              }
            } else if (commandModal.type === 'options') {
              // Options menu modal - navigate sections and fields
              const sections: OptionsSection[] = ['mode', 'swarm', 'ralph', 'devplan', 'settings'];
              const currentSectionIdx = sections.indexOf(optionsSection);
              
              if (k === 'escape') {
                setCommandModal(null);
                setOptionsFocusedField(0);
                appendRalphLines('[CONFIG] Options closed');
                return;
              } else if (k === 'left' || (k === 'h' && !key.ctrl)) {
                // Switch to previous section
                const newIdx = (currentSectionIdx - 1 + sections.length) % sections.length;
                setOptionsSection(sections[newIdx]);
                setOptionsFocusedField(0);
                return;
              } else if (k === 'right' || (k === 'l' && !key.ctrl)) {
                // Switch to next section
                const newIdx = (currentSectionIdx + 1) % sections.length;
                setOptionsSection(sections[newIdx]);
                setOptionsFocusedField(0);
                return;
              } else if (k === 'up') {
                setOptionsFocusedField(prev => Math.max(0, prev - 1));
                return;
              } else if (k === 'down') {
                setOptionsFocusedField(prev => prev + 1);
                return;
              } else if (k === 'return' || k === 'space') {
                // Toggle/cycle the focused field value
                if (optionsSection === 'mode') {
                  const modes: Array<'ralph' | 'devplan' | 'swarm'> = ['ralph', 'devplan', 'swarm'];
                  const currentIdx = modes.indexOf(config.mode);
                  const newMode = modes[(currentIdx + 1) % modes.length];
                  updateConfig({ mode: newMode });
                  appendRalphLines(`[CONFIG] Mode set to: ${newMode}`);
                } else if (optionsSection === 'swarm') {
                  if (optionsFocusedField === 0) {
                    // Cycle provider using dynamic openCodeModels
                    const providers = getProviders();
                    const currentIdx = providers.indexOf(config.swarmModel.provider);
                    const newProvider = providers[(currentIdx + 1) % providers.length];
                    const newModels = getModelsForProvider(newProvider);
                    updateConfig({ swarmModel: { provider: newProvider, model: newModels[0] || '' } });
                  } else if (optionsFocusedField === 1) {
                    // Cycle model for current provider using dynamic models
                    const models = getModelsForProvider(config.swarmModel.provider);
                    const currentIdx = models.indexOf(config.swarmModel.model);
                    const newModel = models[(currentIdx + 1) % models.length] || models[0] || '';
                    updateConfig({ swarmModel: { ...config.swarmModel, model: newModel } });
                  } else if (optionsFocusedField === 2) {
                    // Cycle agent count (1-10)
                    const newCount = (config.swarmAgentCount % 10) + 1;
                    updateConfig({ swarmAgentCount: newCount });
                  }
                } else if (optionsSection === 'ralph') {
                  if (optionsFocusedField === 0) {
                    // Cycle provider using dynamic openCodeModels
                    const providers = getProviders();
                    const currentIdx = providers.indexOf(config.ralphModel.provider);
                    const newProvider = providers[(currentIdx + 1) % providers.length];
                    const newModels = getModelsForProvider(newProvider);
                    updateConfig({ ralphModel: { provider: newProvider, model: newModels[0] || '' } });
                  } else if (optionsFocusedField === 1) {
                    // Cycle model for current provider using dynamic models
                    const models = getModelsForProvider(config.ralphModel.provider);
                    const currentIdx = models.indexOf(config.ralphModel.model);
                    const newModel = models[(currentIdx + 1) % models.length] || models[0] || '';
                    updateConfig({ ralphModel: { ...config.ralphModel, model: newModel } });
                  }
                } else if (optionsSection === 'devplan') {
                  // Granular devplan model selection using dynamic openCodeModels
                  const stages: (keyof DevPlanModels)[] = ['interview', 'design', 'devplan', 'phase', 'handoff'];
                  const stageIdx = Math.floor(optionsFocusedField / 2);
                  const isProvider = optionsFocusedField % 2 === 0;
                  const stage = stages[stageIdx];
                  
                  if (stage) {
                    if (isProvider) {
                      const providers = getProviders();
                      const currentIdx = providers.indexOf(config.devplanModels[stage].provider);
                      const newProvider = providers[(currentIdx + 1) % providers.length];
                      const newModels = getModelsForProvider(newProvider);
                      updateDevplanModel(stage, { provider: newProvider, model: newModels[0] || '' });
                    } else {
                      const models = getModelsForProvider(config.devplanModels[stage].provider);
                      const currentIdx = models.indexOf(config.devplanModels[stage].model);
                      const newModel = models[(currentIdx + 1) % models.length] || models[0] || '';
                      updateDevplanModel(stage, { model: newModel });
                    }
                  }
                } else if (optionsSection === 'settings') {
                  if (optionsFocusedField === 0) {
                    // Refresh OpenCode models
                    refreshOpenCodeModels();
                  } else if (optionsFocusedField === 1) {
                    // Command timeout: cycle through common values
                    const timeouts = [60, 120, 180, 300, 600];
                    const currentIdx = timeouts.indexOf(config.commandTimeout);
                    const newTimeout = timeouts[(currentIdx + 1) % timeouts.length];
                    updateConfig({ commandTimeout: newTimeout });
                  } else if (optionsFocusedField === 2) {
                    // LLM timeout
                    const timeouts = [30, 60, 120, 180, 300];
                    const currentIdx = timeouts.indexOf(config.llmTimeout);
                    const newTimeout = timeouts[(currentIdx + 1) % timeouts.length];
                    updateConfig({ llmTimeout: newTimeout });
                  } else if (optionsFocusedField === 3) {
                    // Poll interval
                    const intervals = [1, 2, 5, 10, 30];
                    const currentIdx = intervals.indexOf(config.pollInterval);
                    const newInterval = intervals[(currentIdx + 1) % intervals.length];
                    updateConfig({ pollInterval: newInterval });
                  } else if (optionsFocusedField === 4) {
                    updateConfig({ autoRefresh: !config.autoRefresh });
                  } else if (optionsFocusedField === 5) {
                    updateConfig({ showCosts: !config.showCosts });
                  } else if (optionsFocusedField === 6) {
                    updateConfig({ debugMode: !config.debugMode });
                  } else if (optionsFocusedField === 7) {
                    // Max log lines
                    const sizes = [100, 200, 500, 1000];
                    const currentIdx = sizes.indexOf(config.maxLogLines);
                    const newSize = sizes[(currentIdx + 1) % sizes.length];
                    updateConfig({ maxLogLines: newSize });
                  }
                }
                return;
              }
            }
          }
          // Close detail view on Escape or q (if detail view is open)
            if (detailView && (key.name === 'escape' || key.name === 'q')) {
              setDetailView(null);
              return;
            }
          
          // BRRRRR - Close help modal on Escape
          if (showHelp && key.name === 'escape') {
            setShowHelp(false);
            return;
          }
          
          if ((key.ctrl && key.name === 'c') || key.name === 'q') {
            // clean shutdown
            try { renderer.stop(); } catch (e) {}
            process.exit(0);
            } else if (key.name === 'tab') {
              if (detailView) return; // Don't switch panes in detail view
              const order: PaneType[] = ['tasks','actions','workers','ralph','console'];
              const idx = order.indexOf(focusedPane);
              setFocusedPane(order[(idx + 1) % order.length]);
            } else if (key.name === 'escape') {
            setDetailView(null);
          } else if (['up','down','pageup','pagedown'].includes(key.name)) {
            if (detailView) return; // Scroll detail view differently if needed
            
            let delta = 0;
            if (key.name === 'up') delta = -1;
            if (key.name === 'down') delta = 1;
            if (key.name === 'pageup') delta = -10;
            if (key.name === 'pagedown') delta = 10;
            
            // Check if shift is held for global scroll, otherwise scroll focused pane
                if (key.shift) {
                  // Global scroll - scroll the main scrollbox
                  const mainScroll = renderer.root.findDescendantById('main-scroll');
                  if (mainScroll && typeof mainScroll.scrollBy === 'function') {
                    try { mainScroll.scrollBy(delta, 'content'); } catch (e) { mainScroll.scrollBy(delta); }
                  }
                  setGlobalScrollOffset(prev => Math.max(0, prev + delta));
                } else {
                  // Pane scroll
                  const paneId = focusedPane;
                  const items = getItemsForPane(paneId);
                  const currentIdx = selectedIndex[paneId] || 0;

              // Update selected index with bounds checking
              const newIdx = Math.max(0, Math.min(Math.max(0, items.length - 1), currentIdx + delta));
              setSelectedIndex(prev => ({ ...prev, [paneId]: newIdx }));

                // Ensure new selection is visible: compute desired scroll offset
                const node = renderer.root.findDescendantById(paneId);
                try {
                  const savedOffset = scrollOffsetsRef.current[paneId] || 0;
                  const visibleSize = PAGE_SIZE;
                  let desiredOffset = savedOffset;
                  if (newIdx < savedOffset) {
                    desiredOffset = newIdx;
                  } else if (newIdx >= savedOffset + visibleSize) {
                    desiredOffset = newIdx - visibleSize + 1;
                  }

                // Clamp desired offset
                const maxOffset = Math.max(0, (items.length || 0) - visibleSize);
                if (desiredOffset < 0) desiredOffset = 0;
                if (desiredOffset > maxOffset) desiredOffset = maxOffset;

                if (node) {
                  if (typeof node.scrollTo === 'function') {
                    try { node.scrollTo(desiredOffset); } catch (e) { /* fallback */ }
                  } else if (typeof node.scrollBy === 'function') {
                    const diff = desiredOffset - (typeof node.scrollOffset === 'number' ? node.scrollOffset : savedOffset);
                    try { node.scrollBy(diff); } catch (e) { /* ignore */ }
                  }
                }

                scrollOffsetsRef.current[paneId] = desiredOffset;
              } catch (err) {
                // Ignore scroll errors but keep selection logic
              }
            }
          } else if (key.name === 'return' || key.name === 'space') {
            // Open detail view for selected item
            const items = getItemsForPane(focusedPane);
            const idx = selectedIndex[focusedPane];
            if (items[idx]) {
              if (focusedPane === 'tasks') {
                setDetailView({ type: 'task', data: items[idx] });
              } else if (focusedPane === 'workers') {
                setDetailView({ type: 'worker', data: items[idx] });
              }
            }
            } else if (key.name === 'r') {
             // manual refresh - force DB reload
             lastDbMtimeRef.current = 0;
            } else if (key.name === 'e') {
              // Emergency stop - confirmation required
              debugLog('Emergency stop requested');
              setCommandModal({
                type: 'confirm',
                title: 'Emergency STOP',
                message: 'Emergency stop will attempt to kill all running workers. Confirm?',
                onConfirm: () => {
                  debugLog('Emergency stop confirmed');
                  appendRalphLines('[UI] Emergency stop confirmed');
                  runCommandStream(ralphCli, ['--emergency-stop'], { showOutput: true, title: 'Emergency Stop', key: 'emergency-stop' });
                },
                onCancel: () => {
                  debugLog('Emergency stop cancelled');
                  appendRalphLines('[UI] Emergency stop cancelled');
                }
              });
            } else if (key.name === 'a') {
              // Attach / inspect - spawn inspect command and stream output
              debugLog('Attach/inspect requested');
              appendRalphLines('[UI] Attaching to swarm (inspect)...');
              runCommandStream(ralphCli, ['--inspect'], { showOutput: true, title: 'Inspect', key: 'inspect' });
            } else if (key.name === 't') {
              // Open task selector modal: let user pick from tasks[]
              debugLog('Task selector requested');
              const opts = (tasks || []).map((t: any) => ({ id: t.id, text: String(t.task_text || '').split('\n')[0].substring(0,80) }));
              if (opts.length === 0) {
                appendRalphLines('[UI] No tasks available to select');
              } else {
                setCommandModal({ type: 'select-task', title: 'Select Task', options: opts, sel: 0 });
              }
            } else if ((key.name || '').toLowerCase() === 'v') {
              // Open run selector modal: pick from recent runs
              try {
                appendRalphLines('[UI] Run selector requested');
                const recent = db.getRecentRuns(20) || [];
                appendRalphLines(`[UI] recent runs found: ${recent.length}`);
                if (recent && recent.length > 0) {
                  appendRalphLines(`[UI] sample runs: ${recent.slice(0,3).map((r:any)=>r.run_id).join(', ')}`);
                }
                if ((recent || []).length === 0) {
                  appendRalphLines('[UI] No recent runs available');
                } else {
                  const opts = recent.map((r: any) => ({ run_id: r.run_id, text: `${r.run_id} ${String(r.status||'').toUpperCase()} ${r.started_at || ''}` }));
                  // offer an option to switch back to live/current run
                  opts.unshift({ run_id: null, text: '(current) Show current run' });
                  setCommandModal({ type: 'select-run', title: 'Select Run', options: opts, sel: 0 });
                }
              } catch (e) { appendRalphLines('[ERR] Failed to fetch recent runs'); }
            } else if (key.name === 's') {
              // Start a run: read project and devplan, then open input modal for configuration
              debugLog('Start-run initiated');
              let pname = '';
              let devplan = '';
              try {
                const projFile = `${process.env.HOME}/projects/current`;
                const fsLocal = require('fs');
                if (fsLocal.existsSync(projFile)) {
                  pname = fsLocal.readFileSync(projFile, 'utf8').trim();
                  const envf = `${process.env.HOME}/projects/${pname}/project.env`;
                  if (fsLocal.existsSync(envf)) {
                    const envC = fsLocal.readFileSync(envf, 'utf8');
                    const m = envC.match(/DEVPLAN_PATH=?(?:\"|\\')?([^\"\\']+)(?:\"|\\')?/);
                    if (m) devplan = m[1];
                  }
                }
              } catch (e) { /* ignore */ }

              // Use swarm agent count from config
              const defaultWorkers = config.swarmAgentCount;
              debugLog(`Start-run: detected project=${pname}, devplan=${devplan}, workers=${defaultWorkers}`);
              
              // Open input modal for start configuration
              setInputBuffer({ project: pname, workers: String(defaultWorkers), devplan: devplan });
              setCommandModal({
                type: 'start-config',
                title: 'Configure Start Run',
                fields: [
                  { key: 'project', label: 'Project Name', value: pname, required: true },
                  { key: 'workers', label: 'Worker Count', value: String(defaultWorkers), required: true },
                  { key: 'devplan', label: 'DevPlan Path', value: devplan, required: false },
                ],
                focusedField: 0,
                onConfirm: (values: any) => {
                  debugLog(`Start-run confirmed: ${JSON.stringify(values)}`);
                  appendRalphLines('[UI] Starting run');
                  // Ensure we have a project name before starting
                  if (!values.project) {
                    appendRalphLines('[ERR] Project name is required; aborting start');
                    debugLog('Start-run aborted: no project name');
                    return;
                  }
                  const workerCount = parseInt(values.workers, 10) || defaultWorkers;
                  // Build args according to ralph-swarm usage: --devplan PATH --project NAME [--workers N]
                  const args: string[] = [];
                  if (values.devplan) { args.push('--devplan', values.devplan); }
                  args.push('--project', values.project);
                  args.push('--workers', String(workerCount));
                  appendRalphLines(`[UI] Invoking: ${ralphCli} ${args.join(' ')}`);
                  runCommandStream(ralphCli, args, { showOutput: true, title: 'Start Run', key: 'start' });
                },
                onCancel: () => { appendRalphLines('[UI] Start run cancelled'); }
              });
            } else if (key.name === 'V') {
              // Clear selected run and show current run
              applySelectedRunId(null);
              appendRalphLines('[UI] Cleared run selection — showing current run');
              lastDbMtimeRef.current = 0;
            } else if (key.name === 'd') {
              // Show modal with instructions to launch interactive interview
              debugLog('Devplan interactive interview help');

              // Auto-detect project directory
              let projectDir = process.cwd();
              let projectName = 'current';
              try {
                const projFile = `${process.env.HOME}/projects/current`;
                const fsLocal = require('fs');
                if (fsLocal.existsSync(projFile)) {
                  projectName = fsLocal.readFileSync(projFile, 'utf8').trim();
                  projectDir = `${process.env.HOME}/projects/${projectName}`;
                }
              } catch (e) { /* ignore */ }

              const interviewCommand = `cd ~/projects/ralphussy/devussy/devussy && python3 -m src.cli interactive-design --llm-interview --streaming --repo-dir ${projectDir}`;

              // Remember where we start adding lines
              const startIdx = ralphLines.length;

              // Add all the instruction lines to ralphLines
              const instructionLines = [
                '',
                '═══════════════════════════════════════════════════════════════',
                '  🎵 DevPlan Interactive Interview - Instructions',
                '═══════════════════════════════════════════════════════════════',
                '',
                '  The interactive interview requires full terminal control.',
                '  To launch it:',
                '',
                '  1. Press ESC or Q to close this TUI',
                '  2. Run this command:',
                '',
                `     ${interviewCommand}`,
                '',
                '  3. The interview will guide you through:',
                '     • Project requirements gathering',
                '     • Technology stack selection',
                '     • Architecture planning',
                '',
                '  4. During the interview:',
                '     • Answer questions naturally in chat',
                '     • Use /help to see available commands',
                '     • Use /done when ready to generate devplan',
                '     • Use /quit to exit without generating',
                '',
                '  5. Outputs will be saved to:',
                `     ~/.ralph/devplans/${projectName}/`,
                '',
                '═══════════════════════════════════════════════════════════════',
                '  Press ESC or Q to close this help',
                '═══════════════════════════════════════════════════════════════',
                '',
              ];

              setRalphLines((prev: string[]) => [...prev, ...instructionLines]);

              // Show output modal starting from where we added the instructions
              setCommandModal({
                type: 'output',
                title: '🎵 DevPlan Interactive Interview',
                startAt: startIdx,
              });
            } else if (key.name === 'o') {
              // Open options menu
              debugLog('Options menu opened');
              appendRalphLines('[UI] Opening options menu...');
              setOptionsSection('mode');
              setOptionsFocusedField(0);
              setCommandModal({
                type: 'options',
                title: 'Options & Settings',
              });
            } else if (key.name === '?') {
              // BRRRRR - Help modal
              setShowHelp(true);
            }
        } catch (err) {
          console.error('keyboard handler error', err);
        }
      });

      // Mouse event handling - BRRRRR mouse support!
      React.useEffect(() => {
        if (!renderer) {
          debugLog('No renderer available for mouse handler');
          return;
        }

        // Try multiple ways to access the blessed screen
        let screen = (renderer as any).screen;
        if (!screen) {
          screen = (renderer as any)._screen;
        }
        if (!screen) {
          screen = (renderer as any).program?.screen;
        }
        if (!screen) {
          // Last resort - try to find screen in renderer properties
          const keys = Object.keys(renderer as any);
          debugLog(`Renderer keys: ${keys.join(', ')}`);
          for (const key of keys) {
            const val = (renderer as any)[key];
            if (val && typeof val === 'object' && val.on && typeof val.on === 'function') {
              screen = val;
              debugLog(`Found potential screen object at renderer.${key}`);
              break;
            }
          }
        }

        if (!screen) {
          debugLog('Could not find screen object for mouse handling');
          appendRalphLines('[MOUSE] Could not initialize mouse handler - screen not found');
          return;
        }

        debugLog(`Screen object found: ${typeof screen}, has 'on': ${typeof screen.on}`);

        const handleMouse = (event: any) => {
          try {
            const { x, y, action } = event;

            // Always log mouse events when options menu is open
            if (commandModal && commandModal.type === 'options') {
              appendRalphLines(`[MOUSE] ${action} at (${x}, ${y}) - Options menu is open`);
            } else if (config.debugMode) {
              appendRalphLines(`[MOUSE] ${action} at (${x}, ${y})`);
            }

            debugLog(`Mouse event: action=${action}, x=${x}, y=${y}, modal=${commandModal?.type || 'none'}`);

            // Only handle click events
            if (action !== 'mousedown' && action !== 'wheeldown' && action !== 'wheelup') {
              return;
            }

            // Check if options modal is open and handle clicks within it
            if (commandModal && commandModal.type === 'options') {
            // Options modal boundaries (approximate from rendering code)
            // Position: left: 3, right: 3, top: 2, bottom: 2
            // This means it spans from x=3 to width-3, y=2 to height-2
            const screenWidth = screen.width;
            const screenHeight = screen.height;
            const modalLeft = 3;
            const modalRight = screenWidth - 3;
            const modalTop = 2;
            const modalBottom = screenHeight - 2;

            // Check if click is within modal bounds
            if (x >= modalLeft && x <= modalRight && y >= modalTop && y <= modalBottom) {
              // Relative position within modal
              const relY = y - modalTop;

              // Header and tabs occupy first ~5 lines, fields start around line 7
              const contentStartLine = 7;

              if (relY >= contentStartLine) {
                const fieldLine = relY - contentStartLine;

                // Each section has different field layouts
                if (optionsSection === 'mode') {
                  // Mode section has 3 options starting around line 7-10
                  // Just clicking anywhere in mode cycles the mode
                  if (action === 'mousedown') {
                    const modes: Array<'ralph' | 'devplan' | 'swarm'> = ['ralph', 'devplan', 'swarm'];
                    const currentIdx = modes.indexOf(config.mode);
                    const nextMode = modes[(currentIdx + 1) % modes.length];
                    setConfig((c: RalphConfig) => ({ ...c, mode: nextMode }));
                    saveConfig({ ...config, mode: nextMode });
                    appendRalphLines(`[CFG] Mode changed to ${nextMode}`);
                  }
                } else if (optionsSection === 'swarm') {
                  // Swarm section has 3 fields: Provider, Model, Agent Count
                  // Clicking on a field line focuses it and cycles the value
                  if (fieldLine >= 0 && fieldLine <= 10 && action === 'mousedown') {
                    let targetField = 0;
                    if (fieldLine >= 0 && fieldLine <= 2) targetField = 0; // Provider
                    else if (fieldLine >= 3 && fieldLine <= 5) targetField = 1; // Model
                    else if (fieldLine >= 6 && fieldLine <= 8) targetField = 2; // Agent Count

                    setOptionsFocusedField(targetField);

                    // Also cycle the value
                    if (targetField === 0) {
                      const providers = getProviders();
                      const idx = providers.indexOf(config.swarmModel.provider);
                      const nextProvider = providers[(idx + 1) % providers.length];
                      const nextModels = getModelsForProvider(nextProvider);
                      setConfig((c: RalphConfig) => ({
                        ...c,
                        swarmModel: { provider: nextProvider, model: nextModels[0] || 'default' }
                      }));
                      saveConfig({ ...config, swarmModel: { provider: nextProvider, model: nextModels[0] || 'default' } });
                    } else if (targetField === 1) {
                      const models = getModelsForProvider(config.swarmModel.provider);
                      const idx = models.indexOf(config.swarmModel.model);
                      const nextModel = models[(idx + 1) % models.length];
                      setConfig((c: RalphConfig) => ({
                        ...c,
                        swarmModel: { ...c.swarmModel, model: nextModel }
                      }));
                      saveConfig({ ...config, swarmModel: { ...config.swarmModel, model: nextModel } });
                    } else if (targetField === 2) {
                      const counts = [1, 2, 3, 4, 5, 8, 10];
                      const idx = counts.indexOf(config.swarmAgentCount);
                      const nextCount = counts[(idx + 1) % counts.length];
                      setConfig((c: RalphConfig) => ({ ...c, swarmAgentCount: nextCount }));
                      saveConfig({ ...config, swarmAgentCount: nextCount });
                    }
                  }
                } else if (optionsSection === 'ralph') {
                  // Ralph section has 2 fields: Provider, Model
                  if (fieldLine >= 0 && fieldLine <= 8 && action === 'mousedown') {
                    let targetField = 0;
                    if (fieldLine >= 0 && fieldLine <= 3) targetField = 0; // Provider
                    else if (fieldLine >= 4 && fieldLine <= 7) targetField = 1; // Model

                    setOptionsFocusedField(targetField);

                    // Cycle value
                    if (targetField === 0) {
                      const providers = getProviders();
                      const idx = providers.indexOf(config.ralphModel.provider);
                      const nextProvider = providers[(idx + 1) % providers.length];
                      const nextModels = getModelsForProvider(nextProvider);
                      setConfig((c: RalphConfig) => ({
                        ...c,
                        ralphModel: { provider: nextProvider, model: nextModels[0] || 'default' }
                      }));
                      saveConfig({ ...config, ralphModel: { provider: nextProvider, model: nextModels[0] || 'default' } });
                    } else if (targetField === 1) {
                      const models = getModelsForProvider(config.ralphModel.provider);
                      const idx = models.indexOf(config.ralphModel.model);
                      const nextModel = models[(idx + 1) % models.length];
                      setConfig((c: RalphConfig) => ({
                        ...c,
                        ralphModel: { ...c.ralphModel, model: nextModel }
                      }));
                      saveConfig({ ...config, ralphModel: { ...config.ralphModel, model: nextModel } });
                    }
                  }
                } else if (optionsSection === 'devplan') {
                  // Devplan section has 5 stages x 2 fields = 10 fields total
                  // Clicking focuses and cycles
                  if (fieldLine >= 0 && fieldLine <= 50 && action === 'mousedown') {
                    const stages: (keyof DevPlanModels)[] = ['interview', 'design', 'devplan', 'phase', 'handoff'];
                    const stageIdx = Math.floor(fieldLine / 5); // Each stage takes ~5 lines
                    const lineInStage = fieldLine % 5;

                    if (stageIdx < stages.length) {
                      const stage = stages[stageIdx];
                      const isProvider = lineInStage <= 1; // First 2 lines are provider
                      const fieldOffset = stageIdx * 2 + (isProvider ? 0 : 1);

                      setOptionsFocusedField(fieldOffset);

                      // Cycle value
                      if (isProvider) {
                        const providers = getProviders();
                        const idx = providers.indexOf(config.devplanModels[stage].provider);
                        const nextProvider = providers[(idx + 1) % providers.length];
                        const nextModels = getModelsForProvider(nextProvider);
                        setConfig((c: RalphConfig) => ({
                          ...c,
                          devplanModels: {
                            ...c.devplanModels,
                            [stage]: { provider: nextProvider, model: nextModels[0] || 'default' }
                          }
                        }));
                        saveConfig({
                          ...config,
                          devplanModels: {
                            ...config.devplanModels,
                            [stage]: { provider: nextProvider, model: nextModels[0] || 'default' }
                          }
                        });
                      } else {
                        const models = getModelsForProvider(config.devplanModels[stage].provider);
                        const idx = models.indexOf(config.devplanModels[stage].model);
                        const nextModel = models[(idx + 1) % models.length];
                        setConfig((c: RalphConfig) => ({
                          ...c,
                          devplanModels: {
                            ...c.devplanModels,
                            [stage]: { ...c.devplanModels[stage], model: nextModel }
                          }
                        }));
                        saveConfig({
                          ...config,
                          devplanModels: {
                            ...config.devplanModels,
                            [stage]: { ...config.devplanModels[stage], model: nextModel }
                          }
                        });
                      }
                    }
                  }
                } else if (optionsSection === 'settings') {
                  // Settings section has 8 fields
                  if (fieldLine >= 0 && fieldLine <= 20 && action === 'mousedown') {
                    const targetField = Math.floor(fieldLine / 2); // Each field takes ~2 lines
                    if (targetField < 8) {
                      setOptionsFocusedField(targetField);

                      // Toggle or cycle based on field
                      if (targetField === 0) {
                        // Refresh models - trigger refresh
                        appendRalphLines('[CFG] Refreshing provider/model list from OpenCode...');
                        refreshProvidersAndModels();
                      } else if (targetField === 1) {
                        // Command timeout - cycle through common values
                        const timeouts = [30, 60, 120, 180, 300, 600];
                        const idx = timeouts.indexOf(config.commandTimeout);
                        const nextTimeout = timeouts[(idx + 1) % timeouts.length];
                        setConfig((c: RalphConfig) => ({ ...c, commandTimeout: nextTimeout }));
                        saveConfig({ ...config, commandTimeout: nextTimeout });
                      } else if (targetField === 2) {
                        // LLM timeout
                        const timeouts = [30, 60, 120, 180, 300, 600];
                        const idx = timeouts.indexOf(config.llmTimeout);
                        const nextTimeout = timeouts[(idx + 1) % timeouts.length];
                        setConfig((c: RalphConfig) => ({ ...c, llmTimeout: nextTimeout }));
                        saveConfig({ ...config, llmTimeout: nextTimeout });
                      } else if (targetField === 3) {
                        // Poll interval
                        const intervals = [1, 2, 3, 5, 10, 15];
                        const idx = intervals.indexOf(config.pollInterval);
                        const nextInterval = intervals[(idx + 1) % intervals.length];
                        setConfig((c: RalphConfig) => ({ ...c, pollInterval: nextInterval }));
                        saveConfig({ ...config, pollInterval: nextInterval });
                      } else if (targetField === 4) {
                        // Auto refresh toggle
                        setConfig((c: RalphConfig) => ({ ...c, autoRefresh: !c.autoRefresh }));
                        saveConfig({ ...config, autoRefresh: !config.autoRefresh });
                      } else if (targetField === 5) {
                        // Show costs toggle
                        setConfig((c: RalphConfig) => ({ ...c, showCosts: !c.showCosts }));
                        saveConfig({ ...config, showCosts: !config.showCosts });
                      } else if (targetField === 6) {
                        // Debug mode toggle
                        setConfig((c: RalphConfig) => ({ ...c, debugMode: !c.debugMode }));
                        saveConfig({ ...config, debugMode: !config.debugMode });
                      } else if (targetField === 7) {
                        // Max log lines
                        const maxes = [100, 200, 500, 1000, 2000, 5000];
                        const idx = maxes.indexOf(config.maxLogLines);
                        const nextMax = maxes[(idx + 1) % maxes.length];
                        setConfig((c: RalphConfig) => ({ ...c, maxLogLines: nextMax }));
                        saveConfig({ ...config, maxLogLines: nextMax });
                      }
                    }
                  }
                }
              }

              // Clicking on tabs (first few lines) switches sections
              if (relY >= 1 && relY <= 3) {
                // Tab line is around relY = 3
                // Approximate tab positions: MODE (~5-15), SWARM (~20-30), RALPH (~35-45), DEVPLAN (~50-60), SETTINGS (~65-75)
                const sections: OptionsSection[] = ['mode', 'swarm', 'ralph', 'devplan', 'settings'];
                const tabWidth = Math.floor(screenWidth / sections.length);
                const clickedTab = Math.floor((x - modalLeft) / tabWidth);

                if (clickedTab >= 0 && clickedTab < sections.length) {
                  setOptionsSection(sections[clickedTab]);
                  setOptionsFocusedField(0);
                }
              }

              // Click outside tabs but inside modal - prevent event from bubbling
              return;
            }

            // Click outside modal - close it
            if (action === 'mousedown') {
              appendRalphLines('[UI] Options menu closed (saved)');
              setCommandModal(null);
            }
          }
          } catch (err) {
            debugLog(`Mouse handler error: ${err}`);
            if (config.debugMode) {
              appendRalphLines(`[MOUSE ERR] ${String(err)}`);
            }
          }
        };

        try {
          screen.on('mouse', handleMouse);
          debugLog('Mouse handler registered successfully');
          appendRalphLines('[MOUSE] Mouse handler initialized - try clicking!');
        } catch (err) {
          debugLog(`Mouse handler setup error: ${err}`);
          appendRalphLines(`[MOUSE ERR] Failed to initialize: ${String(err)}`);
        }

        return () => {
          try {
            screen.off('mouse', handleMouse);
          } catch (err) {
            // Ignore cleanup errors
          }
        };
      }, [renderer, commandModal, optionsSection, optionsFocusedField, config]);

        // DB polling/load function exposed so other actions can trigger it.
        const dbPath = (process.env.RALPH_DIR ? `${process.env.RALPH_DIR.replace(/\/+$/,'')}/swarm.db` : `${os.homedir()}/.ralph/swarm.db`);

        async function load() {
          try {
            // Determine which run to load: either the selected run (historical) or the current run
            let r: any = null;
            try {
                if (selectedRunIdRef.current) {
                  try {
                    // Prefer direct lookup if DB helper provides it
                    if (typeof db.getRunById === 'function') {
                      r = db.getRunById(selectedRunIdRef.current);
                    } else {
                      const recent = db.getRecentRuns(200) || [];
                      r = (recent || []).find((rr: any) => rr.run_id === selectedRunIdRef.current) || null;
                    }
                  } catch (e) {
                    r = null;
                  }
                }
            } catch (e) {
              r = null;
            }
            if (!r) {
              r = db.getCurrentRun();
            }
            if (!mountedRef.current) return;

            // Check DB mtime to avoid heavy work when DB hasn't changed.
            let dbChanged = true;
            try {
              const st = fs.statSync(dbPath);
              const m = st.mtimeMs || st.mtime.getTime();
              if (m === lastDbMtimeRef.current && snapshotRef.current !== null) {
                dbChanged = false;
              } else {
                lastDbMtimeRef.current = m;
                dbChanged = true;
              }
            } catch (e) {
              dbChanged = true;
            }
            pollCounterRef.current++;
            if (pollCounterRef.current % 12 === 0) dbChanged = true;

            if (!dbChanged) return;

            if (r) {
              const workers_ = db.getWorkersByRun(r.run_id) || [];
              const tasks_ = db.getTasksByRun(r.run_id) || [];
              const logs_ = db.getRecentLogs(r.run_id, 100) || [];

              let c: any = null;
              let s: any = null;
              let rc: any[] = [];
              try { c = db.getTotalCosts(r.run_id) || null; } catch (e) { c = null; }
              try { s = db.getTaskStats(r.run_id) || null; } catch (e) { s = null; }
              try { rc = db.getRecentTaskCosts(r.run_id, 5) || []; } catch (e) { rc = []; }

              const snap = {
                run_id: r.run_id,
                total_tasks: r.total_tasks,
                completed_tasks: r.completed_tasks,
                workers_len: workers_.length,
                tasks_len: tasks_.length,
                logs_first: logs_[0]?.log_line || null,
                logs_last: logs_[logs_.length - 1]?.log_line || null,
              };

              const prev = snapshotRef.current;
              const changed = JSON.stringify(prev) !== JSON.stringify(snap);
              if (changed) {
                setRun(r);
                setWorkers(workers_);
                setTasks(tasks_);
                setLogs(logs_);
                setCosts(c || { total_cost: 0, total_prompt_tokens: 0, total_completion_tokens: 0 });
                setStats(s || { pending: 0, in_progress: 0, completed: 0, failed: 0 });
                setRecentCosts(rc || []);
                // Build Ralph Live lines: header + short activity
                const rl: string[] = [];
                rl.push(r ? `Run: ${r.run_id}  Status: ${r.status.toUpperCase()}  Progress: ${r.completed_tasks}/${r.total_tasks}` : 'No active run');
                try {
                  const projFile = `${process.env.HOME}/projects/current`;
                  const fsLocal = require('fs');
                  if (fsLocal.existsSync(projFile)) {
                    const pname = fsLocal.readFileSync(projFile, 'utf8').trim();
                    rl.push(`Project: ${pname}`);
                    const envf = `${process.env.HOME}/projects/${pname}/project.env`;
                    if (fsLocal.existsSync(envf)) {
                      const envC = fsLocal.readFileSync(envf, 'utf8');
                      const m = envC.match(/DEVPLAN_PATH=?"?([^\"]+)"?/);
                      if (m) rl.push(`DevPlan: ${m[1].split('/').pop()}`);
                    }
                  }
                } catch (e) { /* ignore */ }

                  // If a task filter is active, show only logs for that task
                  let snippetSrc = (logs_ || []).slice(-config.maxLogLines);
                  if (selectedTaskIdRef.current !== null) {
                    snippetSrc = snippetSrc.filter((l: any) => l.task_id === selectedTaskIdRef.current);
                  }
                  const snippet = snippetSrc.slice(-8).map((l: any) => `W${String(l.worker_num).padStart(2)} T${String(l.task_id).padStart(4)} ${String(l.log_line || '').split('\n')[0].substring(0,80)}`);
                  if (snippet.length) rl.push('');
                  rl.push(...snippet);
                  setRalphLines(rl);
                }
              snapshotRef.current = snap;

              // Restore scroll positions after meaningful data refresh
              setTimeout(() => {
                for (const paneId of ['actions', 'tasks', 'workers', 'console'] as PaneType[]) {
                  const savedOffset = scrollOffsetsRef.current[paneId];
                  if (savedOffset > 0) {
                    const node = renderer.root.findDescendantById(paneId);
                    if (node && typeof node.scrollTo === 'function') {
                      try { node.scrollTo(savedOffset); } catch (e) {}
                    }
                  }
                }
              }, 50);
            } else {
              if (snapshotRef.current !== null) {
                setRun(null);
                setWorkers([]);
                setTasks([]);
                setLogs([]);
                snapshotRef.current = null;
              }
            }
          } catch (err) {
            console.error('DB load error', err);
          }
        }

        // Start polling
        React.useEffect(() => {
          mountedRef.current = true;
          load();
          // Use config.pollInterval (in seconds) for polling frequency
          const id = setInterval(load, config.pollInterval * 1000);
          return () => {
            mountedRef.current = false;
            clearInterval(id);
          };
        }, [config.pollInterval]);
      
      // Helper to get pane style based on focus state
      const getPaneStyle = (paneId: PaneType) => {
        const isFocused = focusedPane === paneId;
        return {
          borderColor: isFocused ? FOCUS_COLORS.focused.border : FOCUS_COLORS.unfocused.border,
          borderStyle: 'single' as const,
          titleColor: isFocused ? FOCUS_COLORS.focused.title : FOCUS_COLORS.unfocused.title,
        };
      };
      
      // BRRRRR - Enhanced task item formatting with new color scheme
      const formatTaskItem = (t: any, idx: number) => {
        const isSelected = focusedPane === 'tasks' && selectedIndex.tasks === idx;
        const isHovered = hoveredElement === 'tasks';
        const prefix = isSelected ? '▶ ' : '  ';
        const status = t.status || 'unknown';
        
        // Status icons and colors with modern palette
        let statusIcon = '○';
        let statusColor = COLORS.textMuted;
        if (status === 'completed') {
          statusIcon = '✓';
          statusColor = COLORS.success;
        } else if (status === 'in_progress') {
          statusIcon = '◉';
          statusColor = COLORS.accent;
        } else if (status === 'failed') {
          statusIcon = '✗';
          statusColor = COLORS.error;
        } else if (status === 'pending') {
          statusIcon = '○';
          statusColor = COLORS.textMuted;
        }
        
        // BRRRRR - Hover effect
        const bg = isSelected ? COLORS.surfaceActive : (isHovered ? COLORS.surfaceHover : undefined);
        const fg = isSelected ? COLORS.textBright : statusColor;
        
        return {
          content: `${prefix}${statusIcon} ${String(t.id).padStart(3)} ${status.padEnd(11)} ${String(t.task_text || '').split('\n')[0].substring(0, 60)}`,
          fg,
          bg,
        };
      };

      // BRRRRR - Render task elements with hover support and new colors
      const renderTaskElements = (t: any, taskIdx: number) => {
        const elems: any[] = [];
        const isSelected = focusedPane === 'tasks' && selectedIndex.tasks === taskIdx;
        const isHovered = hoveredElement === 'tasks';

        // Determine a sensible wrap width based on renderer width and pane percentage
        const rootWidth = (renderer && (renderer as any).root && (renderer as any).root.width) || 80;
        const approxPaneWidth = Math.max(40, Math.floor(rootWidth * 0.45) - 6);
        const wrapWidth = Math.max(40, approxPaneWidth);

        const text = String(t.task_text || '');
        const primaryLine = text.split('\n')[0].substring(0, wrapWidth);
        const primary = {
          ...formatTaskItem(t, taskIdx),
          content: `${formatTaskItem(t, taskIdx).content.split(' ').slice(0,3).join(' ')} ${primaryLine}`
        };
        elems.push(React.createElement('text', { key: `t-${t.id}-0`, ...primary }));

        // Build remaining content
        let remaining = '';
        if (text.length > wrapWidth) {
          remaining = text.substring(wrapWidth);
        } else {
          const lines = text.split('\n');
          if (lines.length > 1) remaining = lines.slice(1).join('\n');
        }

        if (remaining) {
          const wrapped = remaining.match(new RegExp(`.{1,${wrapWidth}}(?:\\s|$)|\\S+`, 'g')) || [];
          wrapped.forEach((line: string, wi: number) => {
            elems.push(React.createElement('text', {
              key: `t-${t.id}-extra-${wi}`,
              content: `   ${line.trim()}`,
              fg: isSelected ? COLORS.textBright : COLORS.textMuted,
              bg: isSelected ? COLORS.surfaceActive : (isHovered ? COLORS.surfaceHover : undefined),
            }));
          });
        }

        return elems;
      };
      
      // BRRRRR - Enhanced worker formatting with modern colors
      const formatWorkerItem = (w: any, idx: number) => {
        const isSelected = focusedPane === 'workers' && selectedIndex.workers === idx;
        const isHovered = hoveredElement === 'workers';
        const prefix = isSelected ? '▶ ' : '  ';
        
        // Status icons with new color palette
        let statusIcon = '○';
        let statusColor = COLORS.textMuted;
        if (w.status === 'busy') {
          statusIcon = '●';
          statusColor = COLORS.accent;
        } else if (w.status === 'idle') {
          statusIcon = '◉';
          statusColor = COLORS.success;
        } else if (w.status === 'error' || w.status === 'failed') {
          statusIcon = '✖';
          statusColor = COLORS.error;
        } else if (w.status === 'starting') {
          statusIcon = '◐';
          statusColor = COLORS.warning;
        }
        
        const taskInfo = w.current_task_id ? ` → T#${w.current_task_id}` : '';
        const completedInfo = w.completed_tasks ? ` (${w.completed_tasks} done)` : '';
        
        // BRRRRR - Hover effect
        const bg = isSelected ? COLORS.surfaceActive : (isHovered ? COLORS.surfaceHover : undefined);
        const fg = isSelected ? COLORS.textBright : statusColor;
        
        return {
          content: `${prefix}${statusIcon} W${String(w.worker_num).padStart(2)} ${(w.status || 'unknown').padEnd(8)}${taskInfo}${completedInfo}`,
          fg,
          bg,
        };
      };
      
      // Detail view overlay component
      const renderDetailView = () => {
        if (!detailView) return null;
        
        const lines: string[] = [];
        if (detailView.type === 'task') {
          const t = detailView.data;
          const status = t.status || 'unknown';
          const statusIcon = status === 'completed' ? '✓' : status === 'in_progress' ? '◉' : status === 'failed' ? '✗' : '○';
          
          lines.push(`╔═══════════════════════════════════════════════════════════╗`);
          lines.push(`║                     📋 TASK DETAILS                       ║`);
          lines.push(`╠═══════════════════════════════════════════════════════════╣`);
          lines.push(`║                                                           ║`);
          lines.push(`║  ID:          ${String(t.id).padEnd(44)}║`);
          lines.push(`║  Status:      ${statusIcon} ${String(status).padEnd(41)}║`);
          lines.push(`║  Worker:      ${String(t.worker_id || 'N/A').padEnd(44)}║`);
          lines.push(`║  Priority:    ${String(t.priority || 0).padEnd(44)}║`);
          lines.push(`║                                                           ║`);
          lines.push(`╠═══════════════════════════════════════════════════════════╣`);
          lines.push(`║  ⏱ TIMESTAMPS                                             ║`);
          lines.push(`╠═══════════════════════════════════════════════════════════╣`);
          lines.push(`║  Created:     ${String(t.created_at || 'N/A').padEnd(44)}║`);
          lines.push(`║  Started:     ${String(t.started_at || 'N/A').padEnd(44)}║`);
          lines.push(`║  Completed:   ${String(t.completed_at || 'N/A').padEnd(44)}║`);
          lines.push(`║                                                           ║`);
          lines.push(`╠═══════════════════════════════════════════════════════════╣`);
          lines.push(`║  📝 TASK TEXT                                             ║`);
          lines.push(`╠═══════════════════════════════════════════════════════════╣`);
          const taskText = String(t.task_text || '').split('\n');
          for (const line of taskText.slice(0, 15)) {
            lines.push(`║  ${line.substring(0, 57).padEnd(57)}║`);
          }
          if (taskText.length > 15) {
            lines.push(`║  ... (${taskText.length - 15} more lines)${' '.repeat(40)}║`);
          }
          if (t.result) {
            lines.push(`║                                                           ║`);
            lines.push(`╠═══════════════════════════════════════════════════════════╣`);
            lines.push(`║  📤 RESULT                                                ║`);
            lines.push(`╠═══════════════════════════════════════════════════════════╣`);
            const resultLines = String(t.result).split('\n');
            for (const line of resultLines.slice(0, 10)) {
              lines.push(`║  ${line.substring(0, 57).padEnd(57)}║`);
            }
            if (resultLines.length > 10) {
              lines.push(`║  ... (${resultLines.length - 10} more lines)${' '.repeat(40)}║`);
            }
          }
          if (t.error_message) {
            lines.push(`║                                                           ║`);
            lines.push(`╠═══════════════════════════════════════════════════════════╣`);
            lines.push(`║  ❌ ERROR                                                  ║`);
            lines.push(`╠═══════════════════════════════════════════════════════════╣`);
            lines.push(`║  ${String(t.error_message).substring(0, 57).padEnd(57)}║`);
          }
        } else if (detailView.type === 'worker') {
          const w = detailView.data;
          const status = w.status || 'unknown';
          const statusIcon = status === 'busy' ? '●' : status === 'idle' ? '◉' : '○';
          
          lines.push(`╔═══════════════════════════════════════════════════════════╗`);
          lines.push(`║                    🔧 WORKER DETAILS                      ║`);
          lines.push(`╠═══════════════════════════════════════════════════════════╣`);
          lines.push(`║                                                           ║`);
          lines.push(`║  Worker #:       ${String(w.worker_num).padEnd(41)}║`);
          lines.push(`║  Status:         ${statusIcon} ${String(status).padEnd(38)}║`);
          lines.push(`║  PID:            ${String(w.pid || 'N/A').padEnd(41)}║`);
          lines.push(`║  Current Task:   ${String(w.current_task_id || 'None').padEnd(41)}║`);
          lines.push(`║  Tasks Done:     ${String(w.completed_tasks || 0).padEnd(41)}║`);
          lines.push(`║                                                           ║`);
          lines.push(`╠═══════════════════════════════════════════════════════════╣`);
          lines.push(`║  ⏱ TIMESTAMPS                                             ║`);
          lines.push(`╠═══════════════════════════════════════════════════════════╣`);
          lines.push(`║  Started:        ${String(w.started_at || 'N/A').padEnd(41)}║`);
          lines.push(`║  Last Activity:  ${String(w.last_heartbeat || w.last_activity || 'N/A').padEnd(41)}║`);
          lines.push(`║                                                           ║`);
          if (w.branch_name) {
            lines.push(`╠═══════════════════════════════════════════════════════════╣`);
            lines.push(`║  🌿 GIT INFO                                              ║`);
            lines.push(`╠═══════════════════════════════════════════════════════════╣`);
            lines.push(`║  Branch:         ${String(w.branch_name).substring(0, 41).padEnd(41)}║`);
            lines.push(`║                                                           ║`);
          }
          if (w.work_dir) {
            lines.push(`╠═══════════════════════════════════════════════════════════╣`);
            lines.push(`║  📁 WORK DIRECTORY                                        ║`);
            lines.push(`╠═══════════════════════════════════════════════════════════╣`);
            lines.push(`║  ${String(w.work_dir).substring(0, 57).padEnd(57)}║`);
            lines.push(`║                                                           ║`);
          }
        }
        lines.push(`╠═══════════════════════════════════════════════════════════╣`);
        lines.push(`║           Press ESC or q to close this view               ║`);
        lines.push(`╚═══════════════════════════════════════════════════════════╝`);
        
        return React.createElement(
          'box',
          {
            position: 'absolute',
            top: 2,
            left: 5,
            right: 5,
            bottom: 2,
            backgroundColor: '#0d1117',
            borderStyle: 'double',
            borderColor: '#58a6ff',
            zIndex: 100,
          },
          React.createElement(
            'scrollbox',
            { height: '100%', width: '100%' },
            ...lines.map((line, i) => React.createElement('text', { 
              key: `d-${i}`, 
              content: line, 
              fg: i < 3 ? '#58a6ff' : line.includes('═') || line.includes('║') ? '#30363d' : '#c9d1d9' 
            }))
          )
        );
      };

      // Command modal overlay (confirm prompt or live output)
      const renderCommandModal = () => {
        if (!commandModal) return null;
        if (commandModal.type === 'confirm') {
          const lines: string[] = [];
          lines.push('═══════════════════════════════════════════════════════════');
          lines.push(`                    ${String(commandModal.title || 'CONFIRM')}`);
          lines.push('═══════════════════════════════════════════════════════════');
          lines.push('');
          const msg = String(commandModal.message || 'Are you sure?');
          const msgLines = msg.split('\n');
          for (const ml of msgLines) lines.push(`  ${ml}`);
          lines.push('');
          lines.push('  Press Y or Enter to confirm, N or Esc to cancel');
          lines.push('');
          return React.createElement(
            'box',
            {
              position: 'absolute',
              top: 4,
              left: 8,
              right: 8,
              bottom: 6,
              backgroundColor: COLORS.surface,
              borderStyle: 'single',
              borderColor: COLORS.orange,
              zIndex: 120,
            },
            React.createElement('scrollbox', { height: '100%', width: '100%' }, ...lines.map((ln: string, i: number) => React.createElement('text', { key: `cm-${i}`, content: ln, fg: COLORS.warning })))
          );
        } else if (commandModal.type === 'output') {
          const start = typeof commandModal.startAt === 'number' ? commandModal.startAt : 0;
          const out = (ralphLines || []).slice(start);
          return React.createElement(
            'box',
            {
              position: 'absolute',
              top: 3,
              left: 4,
              right: 4,
              bottom: 3,
              backgroundColor: COLORS.surface,
              borderStyle: 'double',
              borderColor: COLORS.accent,
              zIndex: 150,
            },
            React.createElement('text', { content: ` ${commandModal.title || 'Command Output'} `, fg: COLORS.textBright }),
            React.createElement('scrollbox', { height: '90%', width: '100%' }, ...out.map((ln: string, i: number) => React.createElement('text', { key: `out-${i}`, content: ln, fg: i === 0 ? COLORS.textBright : COLORS.text }))),
            React.createElement('text', { content: ' Press ESC or q to close ', fg: COLORS.textMuted })
          );
        } else if (commandModal.type === 'select-task' || commandModal.type === 'select-run') {
          const opts = commandModal.options || [];
          const sel = typeof commandModal.sel === 'number' ? commandModal.sel : 0;
          const title = commandModal.title || (commandModal.type === 'select-task' ? 'Select Task' : 'Select Run');
          const lines: any[] = [];
          lines.push('═══════════════════════════════════════════════════════════');
          lines.push(`                    ${String(title)}`);
          lines.push('═══════════════════════════════════════════════════════════');
          lines.push('');
          // Render a slice window around sel for context
          const start = Math.max(0, sel - 8);
          const end = Math.min(opts.length, start + 16);
          for (let i = start; i < end; i++) {
            const o = opts[i] || {};
            const prefix = i === sel ? '▶' : '  ';
            const text = commandModal.type === 'select-task' ? `${o.id || ''} ${o.text || ''}` : `${o.run_id || ''} ${o.text || ''}`;
            lines.push(`${prefix} ${String(text).substring(0, 120)}`);
          }
          lines.push('');
          lines.push('  Use Up/Down to move, Enter to confirm, Esc to cancel');
          lines.push('');
          return React.createElement(
            'box',
            {
              position: 'absolute',
              top: 3,
              left: 6,
              right: 6,
              bottom: 4,
              backgroundColor: COLORS.surface,
              borderStyle: 'double',
              borderColor: COLORS.accent,
              zIndex: 160,
            },
            React.createElement('scrollbox', { height: '100%', width: '100%' }, ...lines.map((ln: string, i: number) => React.createElement('text', { key: `sel-${i}`, content: ln, fg: i === 0 ? COLORS.textBright : COLORS.text })))
          );
        } else if (commandModal.type === 'start-config') {
          // Input modal for start configuration
          const fields = commandModal.fields || [];
          const focusedField = commandModal.focusedField || 0;
          const lines: string[] = [];
          lines.push('═════════════════════════════════════════════════════════');
          lines.push(`                ${String(commandModal.title || 'Start Configuration')}`);
          lines.push('═════════════════════════════════════════════════════════');
          lines.push('');
          
          for (let i = 0; i < fields.length; i++) {
            const field = fields[i];
            const isFocused = i === focusedField;
            const value = inputBuffer[field.key] ?? field.value ?? '';
            const prefix = isFocused ? '▶ ' : '  ';
            const cursor = isFocused ? '█' : '';
            const required = field.required ? ' *' : '';
            lines.push(`${prefix}${field.label}${required}:`);
            lines.push(`   ${value}${cursor}`);
            lines.push('');
          }
          
          lines.push('───────────────────────────────────────────────────────────');
          lines.push('  Tab/↓ = Next field  ↑ = Previous field');
          lines.push('  Enter = Confirm     Esc = Cancel');
          lines.push('  * = Required field');
          lines.push('───────────────────────────────────────────────────────────');
          
          return React.createElement(
            'box',
            {
              position: 'absolute',
              top: 3,
              left: 6,
              right: 6,
              bottom: 3,
              backgroundColor: COLORS.surface,
              borderStyle: 'double',
              borderColor: COLORS.success,
              zIndex: 170,
            },
            React.createElement('scrollbox', { height: '100%', width: '100%' }, ...lines.map((ln: string, i: number) => React.createElement('text', { key: `cfg-${i}`, content: ln, fg: i < 3 ? COLORS.success : COLORS.text })))
          );
        } else if (commandModal.type === 'devplan-interview') {
          // Devplan interview modal - collect project information
          const fields = commandModal.fields || [];
          const focusedField = commandModal.focusedField || 0;
          const lines: string[] = [];
          
          lines.push('╔═══════════════════════════════════════════════════════════════════╗');
          lines.push('║            📋 DEVPLAN GENERATION - PROJECT INTERVIEW              ║');
          lines.push('╠═══════════════════════════════════════════════════════════════════╣');
          lines.push('║  Fill in the project details below. Tab/↓↑ to navigate fields.   ║');
          lines.push('║  Press Enter on last field or Ctrl+Enter to start generation.    ║');
          lines.push('╠═══════════════════════════════════════════════════════════════════╣');
          lines.push('');
          
          for (let i = 0; i < fields.length; i++) {
            const field = fields[i];
            const isFocused = i === focusedField;
            const value = inputBuffer[field.key] ?? field.value ?? '';
            const prefix = isFocused ? '▶ ' : '  ';
            const cursor = isFocused ? '█' : '';
            const required = field.required ? ' *' : '';
            const hint = field.hint ? ` (${field.hint})` : '';
            
            lines.push(`${prefix}${field.label}${required}:${hint}`);
            
            // For multiline fields, show multiple lines
            if (field.multiline) {
              const valueLines = value.split('\n');
              for (let j = 0; j < Math.max(1, valueLines.length); j++) {
                const lineContent = valueLines[j] || '';
                const showCursor = isFocused && j === valueLines.length - 1;
                lines.push(`   ${lineContent}${showCursor ? cursor : ''}`);
              }
              if (isFocused) {
                lines.push('   (Enter = new line, Ctrl+Enter = submit)');
              }
            } else {
              lines.push(`   ${value}${cursor}`);
            }
            lines.push('');
          }
          
          lines.push('───────────────────────────────────────────────────────────────────');
          lines.push('  Tab/↓ = Next field     ↑ = Previous field');
          lines.push('  Enter = Next/Submit    Esc = Cancel');
          lines.push('  * = Required field');
          lines.push('───────────────────────────────────────────────────────────────────');
          
          return React.createElement(
            'box',
            {
              position: 'absolute',
              top: 2,
              left: 4,
              right: 4,
              bottom: 2,
              backgroundColor: COLORS.surface,
              borderStyle: 'double',
              borderColor: COLORS.purple,
              zIndex: 180,
            },
            React.createElement('scrollbox', { height: '100%', width: '100%' }, ...lines.map((ln: string, i: number) => React.createElement('text', { key: `interview-${i}`, content: ln, fg: i < 6 ? COLORS.purple : COLORS.pink })))
          );
        } else if (commandModal.type === 'devplan-progress') {
          // Devplan progress modal - show pipeline progress
          const lines: string[] = [];
          const stage = devplanProgress.stage;
          const progress = devplanProgress.progress;
          const message = devplanProgress.message;
          
          lines.push('╔═══════════════════════════════════════════════════════════════════╗');
          lines.push('║              🚀 DEVPLAN GENERATION IN PROGRESS                    ║');
          lines.push('╠═══════════════════════════════════════════════════════════════════╣');
          lines.push('');
          
          // Progress stages with visual indicators
          const stages = [
            { key: 'design', label: 'Project Design', icon: '📝' },
            { key: 'devplan', label: 'Basic DevPlan', icon: '📋' },
            { key: 'phases', label: 'Detailed Phases', icon: '🔧' },
            { key: 'handoff', label: 'Handoff Prompt', icon: '📤' },
          ];
          
          for (const s of stages) {
            let status = '○'; // pending
            let color = COLORS.textMuted;
            if (s.key === stage) {
              status = '◉'; // in progress
              color = COLORS.accent;
            } else if (stages.findIndex(x => x.key === stage) > stages.findIndex(x => x.key === s.key)) {
              status = '✓'; // complete
              color = COLORS.success;
            } else if (stage === 'complete') {
              status = '✓';
              color = COLORS.success;
            } else if (stage === 'error') {
              if (stages.findIndex(x => x.key === stage) >= stages.findIndex(x => x.key === s.key)) {
                status = '✗';
                color = COLORS.error;
              }
            }
            lines.push(`  ${status} ${s.icon} ${s.label}`);
          }
          
          lines.push('');
          
          // Progress bar
          const barWidth = 50;
          const filledWidth = Math.floor((progress / 100) * barWidth);
          const emptyWidth = barWidth - filledWidth;
          const progressBar = '█'.repeat(filledWidth) + '░'.repeat(emptyWidth);
          const progressColor = progress >= 100 ? COLORS.success : progress >= 50 ? COLORS.warning : COLORS.accent;
          lines.push(`  [${progressBar}] ${progress}%`);
          lines.push('');
          
          // Current message
          if (message) {
            lines.push(`  📌 ${message}`);
          }
          
          if (stage === 'complete' && devplanProgress.outputPath) {
            lines.push('');
            lines.push(`  ✅ Output saved to: ${devplanProgress.outputPath}`);
          }
          
          if (stage === 'error' && devplanProgress.error) {
            lines.push('');
            lines.push(`  ❌ Error: ${devplanProgress.error}`);
          }
          
          lines.push('');
          lines.push('───────────────────────────────────────────────────────────────────');
          lines.push('  Press ESC to cancel and close');
          lines.push('───────────────────────────────────────────────────────────────────');
          
          return React.createElement(
            'box',
            {
              position: 'absolute',
              top: 3,
              left: 6,
              right: 6,
              bottom: 4,
              backgroundColor: COLORS.surface,
              borderStyle: 'double',
              borderColor: stage === 'error' ? COLORS.error : stage === 'complete' ? COLORS.success : COLORS.accent,
              zIndex: 190,
            },
            React.createElement('scrollbox', { height: '100%', width: '100%' }, ...lines.map((ln: string, i: number) => React.createElement('text', { key: `progress-${i}`, content: ln, fg: i < 3 ? COLORS.accent : COLORS.text })))
          );
        } else if (commandModal.type === 'options') {
          // Options menu modal - settings and configuration
          const lines: string[] = [];
          const sections: OptionsSection[] = ['mode', 'swarm', 'ralph', 'devplan', 'settings'];
          
          // Header with section tabs
          lines.push('╔═════════════════════════════════════════════════════════════════════════════╗');
          lines.push('║                        ⚙️  OPTIONS & SETTINGS                              ║');
          lines.push('╠═════════════════════════════════════════════════════════════════════════╣');
          
          // Section tabs
          const tabLine = sections.map((s, i) => {
            const isActive = s === optionsSection;
            const label = s.toUpperCase();
            return isActive ? `[${label}]` : ` ${label} `;
          }).join('  ');
          lines.push(`║  ${tabLine.padEnd(73)}║`);
          lines.push('╠═══════════════════════════════════════════════════════════════════════════╣');
          lines.push('');
          
          // Section content based on active section
          if (optionsSection === 'mode') {
            lines.push('  🎯 OPERATION MODE');
            lines.push('  ─────────────────────────────────────────────────────────');
            lines.push('');
            const modes: Array<'ralph' | 'devplan' | 'swarm'> = ['ralph', 'devplan', 'swarm'];
            modes.forEach((m, i) => {
              const isSelected = config.mode === m;
              const isFocused = optionsFocusedField === 0 && isSelected;
              const prefix = isSelected ? '◉' : '○';
              const focusIndicator = isFocused ? ' ◄' : '';
              const desc = m === 'ralph' ? 'Single agent autonomous coding' 
                         : m === 'devplan' ? 'Generate development plans from requirements'
                         : 'Multi-agent parallel task execution';
              lines.push(`  ${prefix} ${m.toUpperCase().padEnd(10)} - ${desc}${focusIndicator}`);
            });
            lines.push('');
            lines.push('  Press ENTER/SPACE to cycle modes');
            
          } else if (optionsSection === 'swarm') {
            lines.push('  🐝 SWARM SETTINGS');
            lines.push('  ─────────────────────────────────────────────────────────');
            lines.push('');
            const swarmProviders = getProviders();
            const swarmModels = getModelsForProvider(config.swarmModel.provider);
            const fields = [
              { label: 'Provider', value: config.swarmModel.provider, hint: `(${swarmProviders.length} available)` },
              { label: 'Model', value: config.swarmModel.model, hint: `(${swarmModels.length} for ${config.swarmModel.provider})` },
              { label: 'Agent Count', value: String(config.swarmAgentCount), hint: '' },
            ];
            fields.forEach((f, i) => {
              const isFocused = optionsFocusedField === i;
              const prefix = isFocused ? '▶' : ' ';
              const focusIndicator = isFocused ? ' ◄ (ENTER to cycle)' : '';
              lines.push(`  ${prefix} ${f.label.padEnd(15)}: ${f.value} ${f.hint}${focusIndicator}`);
            });
            lines.push('');
            lines.push('  Available providers: ' + swarmProviders.join(', '));
            if (optionsFocusedField === 1) {
              lines.push('  Models for ' + config.swarmModel.provider + ':');
              swarmModels.slice(0, 5).forEach((m: string) => {
                const isCurrent = m === config.swarmModel.model;
                lines.push(`    ${isCurrent ? '●' : '○'} ${m}`);
              });
              if (swarmModels.length > 5) {
                lines.push(`    ... and ${swarmModels.length - 5} more`);
              }
            }
            
          } else if (optionsSection === 'ralph') {
            lines.push('  🤖 RALPH SETTINGS');
            lines.push('  ─────────────────────────────────────────────────────────');
            lines.push('');
            const ralphProviders = getProviders();
            const ralphModels = getModelsForProvider(config.ralphModel.provider);
            const fields = [
              { label: 'Provider', value: config.ralphModel.provider, hint: `(${ralphProviders.length} available)` },
              { label: 'Model', value: config.ralphModel.model, hint: `(${ralphModels.length} for ${config.ralphModel.provider})` },
            ];
            fields.forEach((f, i) => {
              const isFocused = optionsFocusedField === i;
              const prefix = isFocused ? '▶' : ' ';
              const focusIndicator = isFocused ? ' ◄ (ENTER to cycle)' : '';
              lines.push(`  ${prefix} ${f.label.padEnd(15)}: ${f.value} ${f.hint}${focusIndicator}`);
            });
            lines.push('');
            lines.push('  Ralph uses a single autonomous agent for coding tasks.');
            lines.push('');
            lines.push('  Available providers: ' + ralphProviders.join(', '));
            if (optionsFocusedField === 1) {
              lines.push('  Models for ' + config.ralphModel.provider + ':');
              ralphModels.slice(0, 5).forEach((m: string) => {
                const isCurrent = m === config.ralphModel.model;
                lines.push(`    ${isCurrent ? '●' : '○'} ${m}`);
              });
              if (ralphModels.length > 5) {
                lines.push(`    ... and ${ralphModels.length - 5} more`);
              }
            }
            
          } else if (optionsSection === 'devplan') {
            lines.push('  📋 DEVPLAN MODEL SETTINGS (Granular)');
            lines.push('  ─────────────────────────────────────────────────────────');
            lines.push('  Available providers: ' + getProviders().join(', '));
            lines.push('');
            const stages: (keyof DevPlanModels)[] = ['interview', 'design', 'devplan', 'phase', 'handoff'];
            stages.forEach((stage, si) => {
              const providerIdx = si * 2;
              const modelIdx = si * 2 + 1;
              const stageConfig = config.devplanModels[stage];
              const stageModels = getModelsForProvider(stageConfig.provider);
              
              lines.push(`  📌 ${stage.toUpperCase()}`);
              
              const providerFocused = optionsFocusedField === providerIdx;
              const modelFocused = optionsFocusedField === modelIdx;
              
              const providerPrefix = providerFocused ? '▶' : ' ';
              const modelPrefix = modelFocused ? '▶' : ' ';
              const providerIndicator = providerFocused ? ' ◄' : '';
              const modelIndicator = modelFocused ? ` ◄ (${stageModels.length} models)` : '';
              
              lines.push(`     ${providerPrefix} Provider: ${stageConfig.provider}${providerIndicator}`);
              lines.push(`     ${modelPrefix} Model:    ${stageConfig.model}${modelIndicator}`);
              
              // Show available models when model field is focused
              if (modelFocused && stageModels.length > 0) {
                lines.push('       Available:');
                stageModels.slice(0, 3).forEach((m: string) => {
                  const isCurrent = m === stageConfig.model;
                  lines.push(`         ${isCurrent ? '●' : '○'} ${m}`);
                });
                if (stageModels.length > 3) {
                  lines.push(`         ... and ${stageModels.length - 3} more`);
                }
              }
              lines.push('');
            });
            
          } else if (optionsSection === 'settings') {
            lines.push('  ⚡ GENERAL SETTINGS');
            lines.push('  ─────────────────────────────────────────────────────────');
            lines.push('');
            const providerCount = getProviders().length;
            const totalModels = getProviders().reduce((acc, p) => acc + getModelsForProvider(p).length, 0);
            const fields = [
              { label: 'Refresh Models', value: `${providerCount} providers, ${totalModels} models`, idx: 0, action: true },
              { label: 'Command Timeout', value: `${config.commandTimeout}s`, idx: 1 },
              { label: 'LLM Timeout', value: `${config.llmTimeout}s`, idx: 2 },
              { label: 'Poll Interval', value: `${config.pollInterval}s`, idx: 3 },
              { label: 'Auto Refresh', value: config.autoRefresh ? 'ON' : 'OFF', idx: 4 },
              { label: 'Show Costs', value: config.showCosts ? 'ON' : 'OFF', idx: 5 },
              { label: 'Debug Mode', value: config.debugMode ? 'ON' : 'OFF', idx: 6 },
              { label: 'Max Log Lines', value: String(config.maxLogLines), idx: 7 },
            ];
            fields.forEach((f: any) => {
              const isFocused = optionsFocusedField === f.idx;
              const prefix = isFocused ? '▶' : ' ';
              const focusIndicator = isFocused ? (f.action ? ' ◄ (Press ENTER to refresh from OpenCode)' : ' ◄') : '';
              lines.push(`  ${prefix} ${f.label.padEnd(18)}: ${f.value}${focusIndicator}`);
            });
          }
          
          lines.push('');
          lines.push('═════════════════════════════════════════════════════════════════════════════');
          lines.push('  ←/→ or H/L = Switch section   ↑/↓ = Navigate   ENTER/SPACE = Change value');
          lines.push('  ESC = Close and save          Config: ~/.ralph/config.json');
          lines.push('═════════════════════════════════════════════════════════════════════════');
          
          return React.createElement(
            'box',
            {
              position: 'absolute',
              top: 2,
              left: 3,
              right: 3,
              bottom: 2,
              backgroundColor: COLORS.surface,
              borderStyle: 'double',
              borderColor: COLORS.warning,
              zIndex: 200,
            },
            React.createElement('scrollbox', { height: '100%', width: '100%' }, ...lines.map((ln: string, i: number) => React.createElement('text', { key: `opt-${i}`, content: ln, fg: i < 5 ? COLORS.warning : COLORS.text })))
          );
        }
        return null;
      };
      
      // BRRRRR - Help modal renderer
      const renderHelpModal = () => {
        if (!showHelp) return null;
        
        const lines: any[] = [];
        
        lines.push('╔═════════════════════════════════════════════════════════════════════╗');
        lines.push('║                      📖 RALPH LIVE - KEYBOARD SHORTCUTS                   ║');
        lines.push('╠═════════════════════════════════════════════════════════════════════╣');
        lines.push('');
        lines.push('║  NAVIGATION                                                        ║');
        lines.push('╠═════════════════════════════════════════════════════════════════════╣');
        lines.push('║  Tab        │ Switch between panes (Tasks → Actions → Workers)         ║');
        lines.push('║  Up/Down    │ Navigate through lists in the focused pane               ║');
        lines.push('║  Page Up/Down│ Scroll quickly through lists                            ║');
        lines.push('║  Shift+Up/Down│ Global scroll through the entire dashboard              ║');
        lines.push('║  Enter/Space│ Open detail view for selected item                      ║');
        lines.push('║  Escape     │ Close modals, detail views, or help                     ║');
        lines.push('');
        lines.push('║  ACTIONS                                                          ║');
        lines.push('╠═════════════════════════════════════════════════════════════════════╣');
        lines.push('║  S          │ Start a new run (configure project, workers, devplan)     ║');
        lines.push('║  E          │ Emergency stop - kill all running workers                 ║');
        lines.push('║  A          │ Attach/inspect - attach to running swarm                ║');
        lines.push('║  R          │ Refresh - force reload data from database                ║');
        lines.push('');
        lines.push('║  VIEWS & FILTERS                                                  ║');
        lines.push('╠═════════════════════════════════════════════════════════════════════╣');
        lines.push('║  v          │ View historical runs - select from recent runs            ║');
        lines.push('║  V          │ Clear run selection - return to current run               ║');
        lines.push('║  t          │ Task filter - filter Ralph Live to specific task         ║');
        lines.push('');
        lines.push('║  CONFIGURATION                                                     ║');
        lines.push('╠═════════════════════════════════════════════════════════════════════╣');
        lines.push('║  O          │ Options menu - configure mode, models, settings          ║');
        lines.push('║  D          │ DevPlan generation - create development plans             ║');
        lines.push('');
        lines.push('║  OPTIONS MENU NAVIGATION (when open)                                 ║');
        lines.push('╠═════════════════════════════════════════════════════════════════════╣');
        lines.push('║  Left/Right │ Switch between sections (MODE, SWARM, RALPH, DEVPLAN)  ║');
        lines.push('║  Up/Down    │ Navigate fields within a section                        ║');
        lines.push('║  Enter/Space│ Change/cycle value for selected field                  ║');
        lines.push('║  Escape     │ Close options and save changes                         ║');
        lines.push('');
        lines.push('║  MOUSE SUPPORT                                                     ║');
        lines.push('╠═════════════════════════════════════════════════════════════════════╣');
        lines.push('║  🖱️ Mouse is now enabled! Try clicking on items and scrolling.        ║');
        lines.push('║  Click      │ Select items, open detail views, close modals             ║');
        lines.push('║  Scroll     │ Scroll through panes and lists                          ║');
        lines.push('║  Hover      │ Visual feedback on interactive elements                   ║');
        lines.push('');
        lines.push('╠═════════════════════════════════════════════════════════════════════╣');
        lines.push('║                    Press ESC to close this help                         ║');
        lines.push('╚═════════════════════════════════════════════════════════════════════╝');
        
        return React.createElement(
          'box',
          {
            position: 'absolute',
            top: 1,
            left: 3,
            right: 3,
            bottom: 1,
            backgroundColor: COLORS.background,
            borderStyle: 'double',
            borderColor: COLORS.accent,
            zIndex: 1000,
          },
          React.createElement('scrollbox', { height: '100%', width: '100%' }, ...lines.map((ln: string, i: number) => 
            React.createElement('text', { 
              key: `help-${i}`, 
              content: ln, 
              fg: i < 3 ? COLORS.accent : 
                  ln.includes('═') || ln.includes('║') ? COLORS.border :
                  ln.includes('│') ? COLORS.textMuted :
                  ln.includes('╔') || ln.includes('╗') || ln.includes('╚') || ln.includes('╝') ? COLORS.accent :
                  COLORS.text 
            }))
          )
        );
      };
      

      // Build UI using OpenTUI React primitive component names
      const actionsStyle = getPaneStyle('actions');
      const tasksStyle = getPaneStyle('tasks');
      const workersStyle = getPaneStyle('workers');
      const consoleStyle = getPaneStyle('console');
      
      // Header extras: indicate if user selected a specific run to view
      const headerExtra = selectedRunId ? ` VIEWING RUN: ${selectedRunId}` : '';
      
      // Devplan generation status indicator for header
      const devplanStatusIndicator = devplanStage !== 'idle' && devplanStage !== 'complete' && devplanStage !== 'error'
        ? ` 🚀 DEVPLAN: ${devplanStage.toUpperCase()} ${devplanProgress.progress}%`
        : devplanStage === 'complete' 
          ? ' ✅ DEVPLAN COMPLETE'
          : devplanStage === 'error'
            ? ' ❌ DEVPLAN ERROR'
            : '';
      
      // Determine if viewing a historical (non-running) run for visual affordance
      const isHistoricalRun = selectedRunId && run && run.status !== 'running';
      const headerBgColor = isHistoricalRun ? COLORS.warningDim : (selectedRunId ? COLORS.purpleDim : COLORS.infoDim);
      const headerTextColor = COLORS.textBright;
      
      // BRRRRR - Check if we can show full ASCII title or compact version
      const terminalWidth = (renderer && (renderer as any).root && (renderer as any).root.width) || 80;
      const showAsciiTitle = terminalWidth >= 60;
      const asciiTitle = showAsciiTitle ? RALPH_ASCII_TITLE : RALPH_ASCII_SMALL;
      const asciiLines = asciiTitle.split('\n');
      
      // BRRRRR - Enhanced keyboard shortcuts line with mouse indicator
      const shortcutsLine = 'Keys: [?] Help  [O] Options  [E] Stop  [S] Start  [A] Attach  [D] DevPlan  [v] Run  [t] Task  [r] Refresh  [q] Quit | 🖱️ Mouse ON';

      return React.createElement(
        'box',
        { width: '100%', height: '100%', flexDirection: 'column', backgroundColor: COLORS.background },
        
        // BRRRRR - Help modal overlay
        renderHelpModal(),
        
        // Historical run banner (shown when viewing a non-running historical run)
        isHistoricalRun ? React.createElement(
          'box',
          { height: 1, backgroundColor: COLORS.warning, style: { paddingLeft: 1 } },
          React.createElement('text', { content: '⚠ VIEWING HISTORICAL RUN — Data may be stale. Press V to return to current run.', fg: '#fef3c7' })
        ) : null,
        
        // BRRRRR - ASCII Art Title Header
        showAsciiTitle ? React.createElement(
          'box',
          { height: 7, backgroundColor: COLORS.background, style: { paddingTop: 1, paddingBottom: 1 } },
          ...asciiLines.map((line: string, i: number) => 
            React.createElement('text', { 
              key: `title-${i}`,
              content: line,
              fg: COLORS.accent,
              style: { paddingLeft: 2 }
            })
          )
        ) : React.createElement(
          'box',
          { height: 2, backgroundColor: COLORS.background, style: { paddingTop: 1 } },
          React.createElement('text', { 
            content: asciiTitle,
            fg: COLORS.accent,
            style: { paddingLeft: 2 }
          })
        ),
        
        // Status bar with enhanced colors
        React.createElement(
          'box',
          { height: 2, backgroundColor: headerBgColor, style: { padding: 1 } },
          React.createElement('text', { 
            content: run 
              ? `${spinnerFrame % 2 === 0 ? SPINNER_FRAMES[spinnerFrame % SPINNER_FRAMES.length] : ' '} [${run.status.toUpperCase()}] Mode: ${config.mode.toUpperCase()} | Run: ${run.run_id} | Workers: ${run.worker_count} | Progress: ${run.completed_tasks}/${run.total_tasks} | ${focusedPane.toUpperCase()}${devplanStatusIndicator}${headerExtra}` 
              : `[NO ACTIVE RUN] Mode: ${config.mode.toUpperCase()} | Press "o" for Options, "d" for DevPlan, "s" to Start, "q" to quit.${devplanStatusIndicator}${headerExtra}`, 
            fg: headerTextColor 
          })
        ),
        
        // BRRRRR - Enhanced keyboard shortcuts line with mouse indicator
        React.createElement(
          'box',
          { height: 1, backgroundColor: COLORS.surface, style: { paddingLeft: 1, paddingRight: 1 } },
          React.createElement('text', { content: shortcutsLine, fg: COLORS.textMuted })
        ),
        React.createElement(
          'scrollbox',
          { id: 'main-scroll', width: '100%', height: '100%', flexDirection: 'column' },
        // Middle section with Actions, Tasks, and Workers
          React.createElement(
          'box',
          // Use percentage height instead of growing with item count to avoid
          // creating huge off-screen areas that break scrolling/cursor behavior.
          { flexDirection: 'row', height: '55%' },
            React.createElement(
              'scrollbox',
              { id: 'actions', width: '30%', title: ` ⚡ Live Actions ${focusedPane === 'actions' ? '●' : ''} `, ...actionsStyle },
              ...(logs || []).map((l: any, i: number) => {
                const isSelected = focusedPane === 'actions' && selectedIndex.actions === i;
                const isHovered = hoveredElement === 'actions';
                return React.createElement('text', { 
                  key: `a-${i}`, 
                  content: `W${String(l.worker_num).padStart(2)}  ${String(l.log_line).split('\n')[0]}`, 
                  fg: isSelected ? COLORS.textBright : COLORS.text,
                  bg: isSelected ? COLORS.surfaceActive : (isHovered ? COLORS.surfaceHover : undefined),
                });
              })
            ),
                React.createElement(
                'scrollbox',
                { id: 'tasks', width: '45%', title: ` 📋 Tasks ${focusedPane === 'tasks' ? '●' : ''} `, ...tasksStyle },
                // BRRRRR - Expand tasks with new color scheme
                ...(tasks || []).flatMap((t: any, i: number) => renderTaskElements(t, i))
              ),
            React.createElement(
              'box',
              { width: '25%', flexDirection: 'column' },
                React.createElement('scrollbox', { id: 'resources', height: '60%', title: ' Resources ', borderColor: COLORS.border }, 
                  // BRRRRR - Enhanced resource summary with modern colors
                  ...(() => {
                    const lines: any[] = [];
                    lines.push(React.createElement('text', { key: 'r-h1', content: '╔══════════════════════╗', fg: COLORS.accent }));
                    lines.push(React.createElement('text', { key: 'r-h2', content: '║   📊 RESOURCES      ║', fg: COLORS.accent }));
                    lines.push(React.createElement('text', { key: 'r-h3', content: '╠══════════════════════╣', fg: COLORS.accent }));
                    
                    // Progress bar for task completion - enhanced with gradient colors
                    const total = run?.total_tasks || 1;
                    const completed = run?.completed_tasks || 0;
                    const pct = Math.min(100, Math.floor((completed / total) * 100));
                    const barWidth = 18;
                    const filledWidth = Math.floor((pct / 100) * barWidth);
                    const emptyWidth = barWidth - filledWidth;
                    const progressBar = '█'.repeat(filledWidth) + '░'.repeat(emptyWidth);
                    const progressColor = pct >= 100 ? COLORS.success : pct >= 50 ? COLORS.warning : COLORS.orange;
                    lines.push(React.createElement('text', { key: 'r-prog', content: `║ [${progressBar}] ║`, fg: progressColor }));
                    lines.push(React.createElement('text', { key: 'r-pct', content: `║      ${String(pct).padStart(3)}% Complete   ║`, fg: progressColor }));
                    
                    lines.push(React.createElement('text', { key: 'r-sep0', content: '╠══════════════════════╣', fg: COLORS.accent }));
                    lines.push(React.createElement('text', { key: 'r-cost', content: `║ 💰 Cost: $${(costs?.total_cost || 0).toFixed(2).padStart(9)}║`, fg: COLORS.warning }));
                    lines.push(React.createElement('text', { key: 'r-prompt', content: `║ ⬆ Prompt: ${String(costs?.total_prompt_tokens || 0).padStart(10)}║`, fg: COLORS.textMuted }));
                    lines.push(React.createElement('text', { key: 'r-comp', content: `║ ⬇ Compl:  ${String(costs?.total_completion_tokens || 0).padStart(10)}║`, fg: COLORS.textMuted }));
                    lines.push(React.createElement('text', { key: 'r-sep', content: '╠══════════════════════╣', fg: COLORS.accent }));
                    lines.push(React.createElement('text', { key: 'r-st', content: '║     📋 STATUS        ║', fg: COLORS.accent }));
                    lines.push(React.createElement('text', { key: 'r-st2', content: '╠══════════════════════╣', fg: COLORS.accent }));
                    lines.push(React.createElement('text', { key: 'r-p', content: `║ ⏳ Pending:    ${String(stats?.pending || 0).padStart(5)} ║`, fg: COLORS.textMuted }));
                    lines.push(React.createElement('text', { key: 'r-ip', content: `║ 🔄 In Progress:${String(stats?.in_progress || 0).padStart(4)} ║`, fg: COLORS.accent }));
                    lines.push(React.createElement('text', { key: 'r-c', content: `║ ✅ Completed:  ${String(stats?.completed || 0).padStart(5)} ║`, fg: COLORS.success }));
                    lines.push(React.createElement('text', { key: 'r-f', content: `║ ❌ Failed:     ${String(stats?.failed || 0).padStart(5)} ║`, fg: (stats?.failed || 0) > 0 ? COLORS.error : COLORS.textMuted }));
                    lines.push(React.createElement('text', { key: 'r-sep2', content: '╠══════════════════════╣', fg: COLORS.accent }));
                    lines.push(React.createElement('text', { key: 'r-rc', content: '║    💸 RECENT COSTS   ║', fg: COLORS.accent }));
                    lines.push(React.createElement('text', { key: 'r-sep3', content: '╠══════════════════════╣', fg: COLORS.accent }));
                    if ((recentCosts || []).length === 0) {
                      lines.push(React.createElement('text', { key: 'r-none', content: '║  (no recent costs)   ║', fg: COLORS.textMuted }));
                    } else {
                      (recentCosts || []).forEach((c: any, i: number) => {
                        lines.push(React.createElement('text', { key: `rc-${i}`, content: `║ $${(c.cost || 0).toFixed(4).padStart(6)} T#${String(c.task_id).padStart(4)} ║`, fg: COLORS.warning }));
                      });
                    }
                     lines.push(React.createElement('text', { key: 'r-end', content: '╚══════════════════════╝', fg: COLORS.accent }));
                     return lines;
                   })()
                ),
               React.createElement('scrollbox', { id: 'workers', height: '30%', title: ` 🔧 Workers ${focusedPane === 'workers' ? '●' : ''} `, ...workersStyle }, 
                  ...(workers || []).map((w: any, i: number) => {
                    const fmt = formatWorkerItem(w, i);
                    return React.createElement('text', { key: `w-${i}`, ...fmt });
                  })
                )
             )
          ),
          // BRRRRR - Ralph Live with enhanced colors and styling
          React.createElement(
            'scrollbox',
            { id: 'ralph', height: '40%', title: ` 🟣 Ralph Live ${focusedPane === 'ralph' ? '●' : ''} `, ...consoleStyle, borderColor: COLORS.purple },
            ...(ralphLines.length > 0 ? ralphLines : ['Loading Ralph Live...']).map((ln: string, i: number) => React.createElement('text', {
              key: `rlb-${i}`,
              content: ln,
              fg: i === 0 ? COLORS.textBright : COLORS.pink,
              bg: i === 0 ? COLORS.purpleDim : undefined
            }))
          )
        ),
        // Render detail view overlay if active
        renderDetailView(),
        // Render command modal overlay if active
        renderCommandModal()
      );
    }

    root.render(React.createElement(App));

    // Ensure we restore terminal and stop renderer on signals or crashes so
    // the user isn't left in an unusable terminal state.
    const cleanup = (exitCode = 0) => {
      try {
        renderer.stop();
      } catch (e) {
        // ignore
      }
      try {
        process.exit(exitCode);
      } catch (e) {
        // ignore
      }
    };

    process.on('SIGINT', () => cleanup(0));
    process.on('SIGTERM', () => cleanup(0));
    process.on('uncaughtException', (err) => {
      console.error('Uncaught exception:', err);
      cleanup(1);
    });
    process.on('unhandledRejection', (reason) => {
      console.error('Unhandled rejection:', reason);
      cleanup(1);
    });

    renderer.start();
  } catch (err) {
    console.error('Failed to start swarm-dashboard2:', err);
    process.exit(1);
  }
}

main();
