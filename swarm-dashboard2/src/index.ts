#!/usr/bin/env node

import React from 'react';
import { createRoot, useKeyboard, useRenderer } from '@opentui/react';
import { createCliRenderer, ConsolePosition } from '@opentui/core';

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
      const [focusedPane, setFocusedPane] = React.useState<'actions'|'tasks'|'workers'|'console'>('tasks');

      const renderer = useRenderer();

      // keyboard handling for pane focus and scrolling
      useKeyboard((key) => {
        try {
          if ((key.ctrl && key.name === 'c') || key.name === 'q') {
            // clean shutdown
            try { renderer.stop(); } catch (e) {}
            process.exit(0);
          } else if (key.name === 'tab') {
            const order = ['tasks','actions','workers','console'] as const;
            const idx = order.indexOf(focusedPane);
            setFocusedPane(order[(idx + 1) % order.length]);
          } else if (['up','down','pageup','pagedown'].includes(key.name)) {
            const paneId = focusedPane;
            const node = renderer.root.findDescendantById(paneId);
            if (!node || typeof node.scrollBy !== 'function') return;
            let delta = 0;
            if (key.name === 'up') delta = -1;
            if (key.name === 'down') delta = 1;
            if (key.name === 'pageup') delta = -Math.max(1, Math.floor((node.viewportSize || 10) * 0.8));
            if (key.name === 'pagedown') delta = Math.max(1, Math.floor((node.viewportSize || 10) * 0.8));
            // prefer content unit (lines)
            try { node.scrollBy(delta, 'content'); } catch (e) { node.scrollBy(delta); }
          } else if (key.name === 'r') {
            // manual refresh - trigger a DB reload by forcing state update
            // we'll reload by calling load once; rely on closure load below
            // no-op here because effect polls
          }
        } catch (err) {
          console.error('keyboard handler error', err);
        }
      });

      React.useEffect(() => {
        let mounted = true;
        async function load() {
          try {
            const r = db.getCurrentRun();
            if (!mounted) return;
            if (r) {
              setRun(r);
              setWorkers(db.getWorkersByRun(r.run_id) || []);
              setTasks(db.getTasksByRun(r.run_id) || []);
              setLogs(db.getRecentLogs(r.run_id, 200) || []);
            } else {
              setRun(null);
              setWorkers([]);
              setTasks([]);
              setLogs([]);
            }
          } catch (err) {
            console.error('DB load error', err);
          }
        }
        load();
        const id = setInterval(load, 2000);
        return () => {
          mounted = false;
          clearInterval(id);
        };
      }, []);

      // Build UI using OpenTUI React primitive component names
      return React.createElement(
        'box',
        { width: '100%', height: '100%', flexDirection: 'column' },
        React.createElement(
          'box',
          { height: 3, backgroundColor: '#1e3a5f', style: { padding: 1 } },
          React.createElement('text', { content: run ? `[${run.status.toUpperCase()}] Run: ${run.run_id} | Workers: ${run.worker_count} | Progress: ${run.completed_tasks}/${run.total_tasks}` : '[NO ACTIVE RUN] Press "r" to refresh or "q" to quit', fg: '#ffffff' })
        ),
        React.createElement(
          'box',
          { flexDirection: 'row', height: '60%' },
          React.createElement(
            'scrollbox',
            { id: 'actions', width: '30%', title: ' Live Actions ' },
            ...(logs || []).map((l, i) => React.createElement('text', { key: `a-${i}`, content: `W${String(l.worker_num).padStart(2)}  ${String(l.log_line).split('\n')[0]}`, fg: '#c9d1d9' }))
          ),
          React.createElement(
            'scrollbox',
            { id: 'tasks', width: '45%', title: ' Tasks ' },
            ...(tasks || []).map((t) => React.createElement('text', { key: `t-${t.id}`, content: `${String(t.id).padStart(2)}. ${t.status.padEnd(12)} ${String(t.task_text).split('\n')[0].substring(0, 80)}`, fg: '#8b949e' }))
          ),
          React.createElement(
            'box',
            { width: '25%', flexDirection: 'column' },
            React.createElement('scrollbox', { id: 'resources', height: '60%', title: ' Resources ' }, React.createElement('text', { content: 'Resource summary (coming soon)' })),
            React.createElement('scrollbox', { id: 'workers', height: '40%', title: ' Workers ' }, ...(workers || []).map((w, i) => React.createElement('text', { key: `w-${i}`, content: `${i + 1}. W${String(w.worker_num).padStart(2)} ${w.status} ${w.current_task_id ? `[T#${w.current_task_id}]` : ''}` })))
          )
        ),
        React.createElement('scrollbox', { id: 'console', height: '35%', title: ' Console Log ' }, ...(logs || []).slice(0, 15).map((l, i) => React.createElement('text', { key: `c-${i}`, content: `W${String(l.worker_num).padStart(2)}  ${String(l.log_line).split('\n')[0].substring(0, 80)}` })))
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
