#!/usr/bin/env node

import React from 'react';
import { createRoot, useKeyboard, useRenderer } from '@opentui/react';
import { createCliRenderer, ConsolePosition } from '@opentui/core';
import fs from 'fs';
import os from 'os';

// Type definitions for detail view
type DetailViewType = { type: 'task'; data: any } | { type: 'worker'; data: any } | null;
type PaneType = 'actions' | 'tasks' | 'workers' | 'console' | 'ralph';

// Focus colors for visual indicator
const FOCUS_COLORS = {
  focused: { border: '#58a6ff', title: '#58a6ff', bg: '#0d1117' },
  unfocused: { border: '#30363d', title: '#8b949e', bg: '#161b22' },
};

async function main() {
  try {
    console.error('Starting swarm-dashboard2 (React + OpenTUI)...');

    const renderer = await createCliRenderer({
      consoleOptions: {
        position: ConsolePosition.BOTTOM,
        sizePercent: 20,
      },
      exitOnCtrlC: false,
      useMouse: false,
      enableMouseMovement: false,
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
      // Selected task filter for Ralph Live (null => show all)
      const [selectedTaskId, setSelectedTaskId] = React.useState<number | null>(null);
      const selectedTaskIdRef = React.useRef<number | null>(null);
      const applySelectedTaskId = (id: number | null) => { selectedTaskIdRef.current = id; setSelectedTaskId(id); };
      // Selected run filter (null => show current run)
      const [selectedRunId, setSelectedRunId] = React.useState<string | null>(null);
      const selectedRunIdRef = React.useRef<string | null>(null);
      const applySelectedRunId = (id: string | null) => { selectedRunIdRef.current = id; setSelectedRunId(id); };

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
          // keep last 200 lines
          return merged.slice(-200);
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
                    // item.run_id === null means show current (all) runs
                    applySelectedRunId(item.run_id || null);
                    selectedRunIdRef.current = item.run_id || null;
                    appendRalphLines(`[UI] Showing run: ${item.run_id || '(current)'} `);
                    // force immediate reload
                    lastDbMtimeRef.current = 0;
                  }
                } catch (e) {}
                setCommandModal(null);
                return;
              } else if (k === 'escape' || k === 'q') {
                setCommandModal(null);
                return;
              }
            }
          }
          // Close detail view on Escape or q (if detail view is open)
            if (detailView && (key.name === 'escape' || key.name === 'q')) {
              setDetailView(null);
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
              setCommandModal({
                type: 'confirm',
                title: 'Emergency STOP',
                message: 'Emergency stop will attempt to kill all running workers. Confirm?',
                onConfirm: () => {
                  appendRalphLines('[UI] Emergency stop confirmed');
                  runCommandStream(ralphCli, ['--emergency-stop'], { showOutput: true, title: 'Emergency Stop', key: 'emergency-stop' });
                },
                onCancel: () => {
                  appendRalphLines('[UI] Emergency stop cancelled');
                }
              });
            } else if (key.name === 'a') {
              // Attach / inspect - spawn inspect command and stream output
              appendRalphLines('[UI] Attaching to swarm (inspect)...');
              runCommandStream(ralphCli, ['--inspect'], { showOutput: true, title: 'Inspect', key: 'inspect' });
            } else if (key.name === 't') {
              // Open task selector modal: let user pick from tasks[]
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
              // Start a run: read project and devplan, then ask for confirmation
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
                    const m = envC.match(/DEVPLAN_PATH=?(?:\"|\')?([^\"\']+)(?:\"|\')?/);
                    if (m) devplan = m[1];
                  }
                }
              } catch (e) { /* ignore */ }

              const defaultWorkers = 4;
              // Build confirmation message using the values we just resolved
              const msg = `Start swarm with DevPlan: ${devplan || '(none)'}  Project: ${pname || '(unknown)'}  Workers: ${defaultWorkers}?`;
              setCommandModal({
                type: 'confirm',
                title: 'Start Run',
                message: msg,
                onConfirm: () => {
                  appendRalphLines('[UI] Starting run');
                  // Ensure we have a project name before starting
                  if (!pname) {
                    appendRalphLines('[ERR] Could not determine project name; aborting start');
                    return;
                  }
                  // Build args according to ralph-swarm usage: --devplan PATH --project NAME [--workers N]
                  const args: string[] = [];
                  if (devplan) { args.push('--devplan', devplan); }
                  args.push('--project', pname);
                  args.push('--workers', String(defaultWorkers));
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
            }
        } catch (err) {
          console.error('keyboard handler error', err);
        }
      });

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
                  let snippetSrc = (logs_ || []).slice(-200);
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
          const id = setInterval(load, 5000);
          return () => {
            mountedRef.current = false;
            clearInterval(id);
          };
        }, []);
      
      // Helper to get pane style based on focus state
      const getPaneStyle = (paneId: PaneType) => {
        const isFocused = focusedPane === paneId;
        return {
          borderColor: isFocused ? FOCUS_COLORS.focused.border : FOCUS_COLORS.unfocused.border,
          borderStyle: 'single' as const,
          titleColor: isFocused ? FOCUS_COLORS.focused.title : FOCUS_COLORS.unfocused.title,
        };
      };
      
      // Helper to format task item with selection indicator
      const formatTaskItem = (t: any, idx: number) => {
        const isSelected = focusedPane === 'tasks' && selectedIndex.tasks === idx;
        const prefix = isSelected ? '▶ ' : '  ';
        const status = t.status || 'unknown';
        const statusColor = status === 'completed' ? '#3fb950' : status === 'in_progress' ? '#58a6ff' : status === 'failed' ? '#f85149' : '#8b949e';
        return {
          content: `${prefix}${String(t.id).padStart(2)}. ${status.padEnd(12)} ${String(t.task_text || '').split('\n')[0].substring(0, 70)}`,
          fg: isSelected ? '#ffffff' : statusColor,
          bg: isSelected ? '#30363d' : undefined,
        };
      };

      // Render a task as multiple text lines (wrapping) and highlight all lines when selected.
      // Compute wrap width dynamically from renderer root width so the tasks pane uses
      // the full horizontal space it has instead of a fixed 70-char column.
      const renderTaskElements = (t: any, taskIdx: number) => {
        const elems: any[] = [];
        const isSelected = focusedPane === 'tasks' && selectedIndex.tasks === taskIdx;

        // Determine a sensible wrap width based on renderer width and pane percentage
        const rootWidth = (renderer && (renderer as any).root && (renderer as any).root.width) || 80;
        // tasks pane uses ~45% of terminal width; leave padding for indexes and margins
        const approxPaneWidth = Math.max(40, Math.floor(rootWidth * 0.45) - 6);
        const wrapWidth = Math.max(40, approxPaneWidth);

        const text = String(t.task_text || '');
        const primaryLine = text.split('\n')[0].substring(0, wrapWidth);
        const primary = {
          ...formatTaskItem(t, taskIdx),
          content: `${formatTaskItem(t, taskIdx).content.split(' ').slice(0,3).join(' ')} ${primaryLine}`
        };
        elems.push(React.createElement('text', { key: `t-${t.id}-0`, ...primary }));

        // Build remaining content (after first wrapWidth chars) including subsequent lines
        let remaining = '';
        if (text.length > wrapWidth) {
          remaining = text.substring(wrapWidth);
        } else {
          const lines = text.split('\n');
          if (lines.length > 1) remaining = lines.slice(1).join('\n');
        }

        if (remaining) {
          // Wrap remaining into wrapWidth chunks
          const wrapped = remaining.match(new RegExp(`.{1,${wrapWidth}}(?:\\s|$)|\\S+`, 'g')) || [];
          wrapped.forEach((line: string, wi: number) => {
            elems.push(React.createElement('text', {
              key: `t-${t.id}-extra-${wi}`,
              content: `   ${line.trim()}`,
              fg: isSelected ? '#ffffff' : '#8b949e',
              bg: isSelected ? '#30363d' : undefined,
            }));
          });
        }

        return elems;
      };
      
      // Helper to format worker item with selection indicator
      const formatWorkerItem = (w: any, idx: number) => {
        const isSelected = focusedPane === 'workers' && selectedIndex.workers === idx;
        const prefix = isSelected ? '▶ ' : '  ';
        const statusColor = w.status === 'busy' ? '#58a6ff' : w.status === 'idle' ? '#3fb950' : '#8b949e';
        return {
          content: `${prefix}${idx + 1}. W${String(w.worker_num).padStart(2)} ${w.status} ${w.current_task_id ? `[T#${w.current_task_id}]` : ''}`,
          fg: isSelected ? '#ffffff' : statusColor,
          bg: isSelected ? '#30363d' : undefined,
        };
      };
      
      // Detail view overlay component
      const renderDetailView = () => {
        if (!detailView) return null;
        
        const lines: string[] = [];
        if (detailView.type === 'task') {
          const t = detailView.data;
          lines.push(`═══════════════════════════════════════════════════════════`);
          lines.push(`                    TASK DETAILS`);
          lines.push(`═══════════════════════════════════════════════════════════`);
          lines.push(``);
          lines.push(`  ID:          ${t.id}`);
          lines.push(`  Status:      ${t.status}`);
          lines.push(`  Worker:      ${t.worker_id || 'N/A'}`);
          lines.push(`  Created:     ${t.created_at || 'N/A'}`);
          lines.push(`  Started:     ${t.started_at || 'N/A'}`);
          lines.push(`  Completed:   ${t.completed_at || 'N/A'}`);
          lines.push(``);
          lines.push(`  ─────────────────────────────────────────────────────────`);
          lines.push(`  Task Text:`);
          lines.push(`  ─────────────────────────────────────────────────────────`);
          const taskText = String(t.task_text || '').split('\n');
          for (const line of taskText) {
            lines.push(`  ${line}`);
          }
          if (t.result) {
            lines.push(``);
            lines.push(`  ─────────────────────────────────────────────────────────`);
            lines.push(`  Result:`);
            lines.push(`  ─────────────────────────────────────────────────────────`);
            const resultLines = String(t.result).split('\n');
            for (const line of resultLines.slice(0, 20)) {
              lines.push(`  ${line}`);
            }
            if (resultLines.length > 20) {
              lines.push(`  ... (${resultLines.length - 20} more lines)`);
            }
          }
        } else if (detailView.type === 'worker') {
          const w = detailView.data;
          lines.push(`═══════════════════════════════════════════════════════════`);
          lines.push(`                   WORKER DETAILS`);
          lines.push(`═══════════════════════════════════════════════════════════`);
          lines.push(``);
          lines.push(`  Worker #:       ${w.worker_num}`);
          lines.push(`  Status:         ${w.status}`);
          lines.push(`  Current Task:   ${w.current_task_id || 'None'}`);
          lines.push(`  Tasks Done:     ${w.completed_tasks || 0}`);
          lines.push(`  Started:        ${w.started_at || 'N/A'}`);
          lines.push(`  Last Activity:  ${w.last_activity || 'N/A'}`);
        }
        lines.push(``);
        lines.push(`  ─────────────────────────────────────────────────────────`);
        lines.push(`  Press ESC or q to close`);
        lines.push(`  ─────────────────────────────────────────────────────────`);
        
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
            ...lines.map((line, i) => React.createElement('text', { key: `d-${i}`, content: line, fg: '#c9d1d9' }))
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
              backgroundColor: '#0b1220',
              borderStyle: 'single',
              borderColor: '#f97316',
              zIndex: 120,
            },
            React.createElement('scrollbox', { height: '100%', width: '100%' }, ...lines.map((ln: string, i: number) => React.createElement('text', { key: `cm-${i}`, content: ln, fg: '#ffd8a8' })))
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
              backgroundColor: '#071029',
              borderStyle: 'double',
              borderColor: '#60a5fa',
              zIndex: 150,
            },
            React.createElement('text', { content: ` ${commandModal.title || 'Command Output'} `, fg: '#ffffff' }),
            React.createElement('scrollbox', { height: '90%', width: '100%' }, ...out.map((ln: string, i: number) => React.createElement('text', { key: `out-${i}`, content: ln, fg: i === 0 ? '#ffffff' : '#c7d2fe' }))),
            React.createElement('text', { content: ' Press ESC or q to close ', fg: '#9ca3af' })
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
              backgroundColor: '#071029',
              borderStyle: 'double',
              borderColor: '#60a5fa',
              zIndex: 160,
            },
            React.createElement('scrollbox', { height: '100%', width: '100%' }, ...lines.map((ln: string, i: number) => React.createElement('text', { key: `sel-${i}`, content: ln, fg: i === 0 ? '#ffffff' : '#c7d2fe' })))
          );
        }
        return null;
      };

      // Build UI using OpenTUI React primitive component names
      const actionsStyle = getPaneStyle('actions');
      const tasksStyle = getPaneStyle('tasks');
      const workersStyle = getPaneStyle('workers');
      const consoleStyle = getPaneStyle('console');
      
      // Header extras: indicate if user selected a specific run to view
      const headerExtra = selectedRunId ? ` VIEWING RUN: ${selectedRunId}` : '';

      return React.createElement(
        'box',
        { width: '100%', height: '100%', flexDirection: 'column' },
        React.createElement(
          'box',
          { height: 3, backgroundColor: '#1e3a5f', style: { padding: 1 } },
          React.createElement('text', { 
            content: run 
              ? `[${run.status.toUpperCase()}] Run: ${run.run_id} | Workers: ${run.worker_count} | Progress: ${run.completed_tasks}/${run.total_tasks} | ${focusedPane.toUpperCase()} (Tab=switch, Arrows=scroll, Shift+Arrows=scroll all) Keys: [E]merg [S]tart [A]ttach [R]efresh${headerExtra}` 
              : `[NO ACTIVE RUN] Press "r" to refresh or "q" to quit. Keys: [E]merg [S]tart [A]ttach [R]efresh${headerExtra}`, 
            fg: '#ffffff' 
          })
        ),
        // Keymap line to show available keyboard shortcuts
        React.createElement(
          'box',
          { height: 1, backgroundColor: '#0b1220', style: { paddingLeft: 1, paddingRight: 1 } },
          React.createElement('text', { content: 'Keys: [E] Emergency-stop  [S] Start  [A] Attach/Inspect  [v] Select Run  [V] Clear Run  [t] Select Task  [r] Refresh  [q] Quit', fg: '#cbd5e1' })
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
              { id: 'actions', width: '30%', title: ` Live Actions ${focusedPane === 'actions' ? '●' : ''} `, ...actionsStyle },
              ...(logs || []).map((l: any, i: number) => React.createElement('text', { 
                key: `a-${i}`, 
                content: `W${String(l.worker_num).padStart(2)}  ${String(l.log_line).split('\n')[0]}`, 
                fg: focusedPane === 'actions' && selectedIndex.actions === i ? '#ffffff' : '#c9d1d9',
                bg: focusedPane === 'actions' && selectedIndex.actions === i ? '#30363d' : undefined,
              }))
            ),
               React.createElement(
               'scrollbox',
               { id: 'tasks', width: '45%', title: ` Tasks ${focusedPane === 'tasks' ? '●' : ''} `, ...tasksStyle },
               // Expand each task into multiple text elements to support wrapping
               ...(tasks || []).flatMap((t: any, i: number) => renderTaskElements(t, i))
             ),
            React.createElement(
              'box',
              { width: '25%', flexDirection: 'column' },
               React.createElement('scrollbox', { id: 'resources', height: '60%', title: ' Resources ', borderColor: '#30363d' }, 
                 // Build resource summary lines
                 ...(() => {
                   const lines: any[] = [];
                   lines.push(React.createElement('text', { key: 'r-h1', content: '╔══════════════════════╗', fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-h2', content: '║   RESOURCE SUMMARY   ║', fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-h3', content: '╠══════════════════════╣', fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-empty', content: '║                      ║', fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-cost', content: `║ Total Cost: $${(costs?.total_cost || 0).toFixed(2).padStart(8)}║`, fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-empty2', content: '║                      ║', fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-prompt', content: `║ Prompt Tokens: ${String(costs?.total_prompt_tokens || 0).padStart(12)}║`, fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-empty3', content: '║                      ║', fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-comp', content: `║ Completion Tokens: ${String(costs?.total_completion_tokens || 0).padStart(8)}║`, fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-sep', content: '╠══════════════════════╣', fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-st', content: '║   TASK STATUS         ║', fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-st2', content: '╠══════════════════════╣', fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-p', content: `║ Pending: ${String(stats?.pending || 0).padStart(10)}║`, fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-ip', content: `║ In Progress: ${String(stats?.in_progress || 0).padStart(5)}║`, fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-c', content: `║ Completed: ${String(stats?.completed || 0).padStart(7)}║`, fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-f', content: `║ Failed: ${String(stats?.failed || 0).padStart(10)}║`, fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-sep2', content: '╠══════════════════════╣', fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-rc', content: '║   RECENT COSTS        ║', fg: '#c9d1d9' }));
                   lines.push(React.createElement('text', { key: 'r-sep3', content: '╠══════════════════════╣', fg: '#c9d1d9' }));
                   if ((recentCosts || []).length === 0) {
                     lines.push(React.createElement('text', { key: 'r-none', content: '║ (no recent costs)     ║', fg: '#8b949e' }));
                   } else {
                     (recentCosts || []).forEach((c: any, i: number) => {
                       lines.push(React.createElement('text', { key: `rc-${i}`, content: `║ $${(c.cost || 0).toFixed(4).padStart(6)} T:${String(c.task_id).padStart(4)}║`, fg: '#c9d1d9' }));
                     });
                   }
                    lines.push(React.createElement('text', { key: 'r-end', content: '╚══════════════════════╝', fg: '#c9d1d9' }));
                    return lines;
                  })()
                ),
               React.createElement('scrollbox', { id: 'workers', height: '30%', title: ` Workers ${focusedPane === 'workers' ? '●' : ''} `, ...workersStyle }, 
                 ...(workers || []).map((w: any, i: number) => {
                   const fmt = formatWorkerItem(w, i);
                   return React.createElement('text', { key: `w-${i}`, ...fmt });
                 })
               )
             )
          ),
          // Console section - show all logs, not just 15
          // Ralph Live replaces the previous Console Log panel and now occupies
          // the full-width bottom area. It shows run/project/model/state +
          // a short activity stream.
          React.createElement(
            'scrollbox',
            { id: 'ralph', height: '40%', title: ` Ralph Live ${focusedPane === 'ralph' ? '●' : ''} `, ...consoleStyle, borderColor: '#a855f7' },
            ...(ralphLines.length > 0 ? ralphLines : ['Loading Ralph Live...']).map((ln: string, i: number) => React.createElement('text', {
              key: `rlb-${i}`,
              content: ln,
              fg: i === 0 ? '#ffffff' : '#e9d5ff'
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
