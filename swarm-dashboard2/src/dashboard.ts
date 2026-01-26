import { createCliRenderer, Box, Text, type BoxOptions, type TextOptions, ConsolePosition } from '@opentui/core';

export class SwarmDashboard2 {
  private renderer!: Awaited<ReturnType<typeof createCliRenderer>>;
  private db!: ReturnType<typeof createSwarmDatabase>;
  private refreshInterval: number = 5000; // reduce refresh frequency to lower CPU usage
  private paused: boolean = false;
  private lastKeyHandledAt: number = 0;
  private keyThrottleMs: number = 80; // throttle repeated key handling
  private refreshTimer: NodeJS.Timeout | null = null;
  private currentRunId: string | null = null;
  private lastLogTimestamp: number = 0;
  private logLines: Array<{ worker_num: string; log_line: string }> = [];
  // Scrolling / focus state for panes
  private paneOffsets: Record<string, number> = { actions: 0, tasks: 0, workers: 0, console: 0, ralph: 0 };
  // Track how many renderable lines each pane currently has so we can clamp scrolling
  private paneCounts: Record<string, number> = { actions: 0, tasks: 0, workers: 0, console: 0, ralph: 0 };
  private focusedPane: 'actions' | 'tasks' | 'workers' | 'console' | 'ralph' = 'tasks';
  // Ralph-live state
  private ralphLiveState: {
    currentProject: string;
    workdir: string;
    devplanPath: string;
    provider: string;
    model: string;
    swarmProvider: string;
    swarmModel: string;
  } = {
    currentProject: '',
    workdir: '',
    devplanPath: '',
    provider: '',
    model: '',
    swarmProvider: '',
    swarmModel: '',
  };
  private pageSize: number = 20;

  async init() {
    try {
      this.renderer = await createCliRenderer({
        consoleOptions: {
          position: ConsolePosition.BOTTOM,
          sizePercent: 20,
        },
        exitOnCtrlC: false,
        useMouse: false,
        enableMouseMovement: false,
        useAlternateScreen: true,
      });

      // Dynamically import the compiled DB helper so Bun resolves the
      // compiled JS module at runtime and we avoid static resolution issues.
      const dbMod = await import('../../swarm-dashboard/dist/database-bun.js');
      this.db = dbMod.createSwarmDatabase();
      
      // Setup exit handlers
      process.on('exit', () => this.cleanup());
      process.on('SIGINT', () => {
        this.cleanup();
        process.exit(0);
      });
      process.on('SIGTERM', () => {
        this.cleanup();
        process.exit(0);
      });
    } catch (error) {
      console.error('Failed to initialize dashboard:', error);
      process.exit(1);
    }

    this.setupKeyboardHandlers();
    this.createLayout();
    this.startRefreshLoop();
    this.renderer.start();
  }

  private setupKeyboardHandlers() {
    this.renderer.keyInput.on('keypress', (key) => {
      const now = Date.now();
      // Throttle rapid key repeats to avoid flooding refreshes
      if (now - this.lastKeyHandledAt < this.keyThrottleMs) return;
      this.lastKeyHandledAt = now;

      if (key.ctrl && key.name === 'c') {
        this.cleanup();
        process.exit(0);
      } else if (key.name === 'q') {
        this.cleanup();
        process.exit(0);
      } else if (key.name === 'r') {
        this.refreshData();
      } else if (key.name === 'p') {
        // Toggle pause polling
        this.paused = !this.paused;
        if (this.paused) {
          if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = null;
          }
        } else {
          this.startRefreshLoop();
        }
        this.refreshData();
      } else if (key.name === 'tab') {
        // Cycle focus: tasks -> actions -> workers -> ralph -> console
        const order: Array<typeof this.focusedPane> = ['tasks', 'actions', 'workers', 'ralph', 'console'];
        const idx = order.indexOf(this.focusedPane);
        this.focusedPane = order[(idx + 1) % order.length];
        this.refreshData();
        } else if (key.name === 'up' || key.name === 'down' || key.name === 'pageup' || key.name === 'pagedown') {
          // Scroll the focused pane
          let delta = 0;
          if (key.name === 'up') delta = -1;
          else if (key.name === 'down') delta = 1;
          else if (key.name === 'pageup') delta = -Math.max(1, Math.floor(this.pageSize * 0.8));
          else if (key.name === 'pagedown') delta = Math.max(1, Math.floor(this.pageSize * 0.8));

        // If Shift is held, scroll all panes together
        if (key.shift) {
          for (const pane of Object.keys(this.paneOffsets)) {
            const curOff = this.paneOffsets[pane] || 0;
            let nextOff = curOff + delta;
            const maxOff = Math.max(0, (this.paneCounts[pane] || 0) - this.pageSize);
            if (nextOff < 0) nextOff = 0;
            if (nextOff > maxOff) nextOff = maxOff;
            this.paneOffsets[pane] = nextOff;
          }
        } else {
          const cur = this.paneOffsets[this.focusedPane] || 0;
          let next = cur + delta;
          const maxOff = Math.max(0, (this.paneCounts[this.focusedPane] || 0) - this.pageSize);
          if (next < 0) next = 0;
          if (next > maxOff) next = maxOff;
          this.paneOffsets[this.focusedPane] = next;
        }

    if (!this.paused) this.refreshData();
      }
    });
  }

  private createLayout() {
    const { root } = this.renderer;

    const headerBox = Box({
      id: 'header',
      width: '100%',
      height: 5,
      backgroundColor: '#1e3a5f',
      borderStyle: 'single',
      borderColor: '#4a90d9',
      position: 'absolute',
      top: 0,
      left: 0,
    });

    const statusText = Text({
      id: 'status',
      content: 'Initializing...',
      fg: '#ffffff',
      position: 'absolute',
      left: 2,
      top: 1,
    });

    this.renderer.root.add(headerBox);
    this.renderer.root.add(statusText);

    const mainContainer = Box({
      id: 'main',
      flexDirection: 'column',
      width: '100%',
      height: '100%',
      position: 'absolute',
      top: 5,
      left: 0,
    });

    // Layout: left = actions stream, middle = tasks, right = vertical column (resources over workers)
    const middleContainer = Box({
      id: 'middle',
      flexDirection: 'row',
      width: '100%',
      height: '60%',
      position: 'relative',
    });

    const actionsPanel = Box({
      id: 'actions-panel',
      width: '30%',
      height: '100%',
      backgroundColor: '#071129',
      borderStyle: 'double',
      borderColor: '#39a0ed',
      title: ' Live Actions ',
      position: 'relative',
    });

    const actionsList = Box({
      id: 'actions-list',
      flexDirection: 'column',
      width: '100%',
      height: '100%',
      position: 'absolute',
      top: 1,
      left: 0,
    });

    actionsPanel.add(actionsList);

    const tasksPanel = Box({
      id: 'tasks-panel',
      width: '45%',
      height: '100%',
      backgroundColor: '#0d1117',
      borderStyle: 'double',
      borderColor: '#238636',
      title: ' Tasks ',
      position: 'relative',
    });

    const tasksHeader = Text({
      id: 'tasks-header',
      content: 'ID  Status      Description',
      fg: '#8b949e',
      position: 'absolute',
      left: 1,
      top: 1,
    });

    tasksPanel.add(tasksHeader);

    const tasksList = Box({
      id: 'tasks-list',
      flexDirection: 'column',
      width: '100%',
      height: '100%',
      position: 'absolute',
      top: 3,
      left: 0,
    });

    tasksPanel.add(tasksList);

    const rightColumn = Box({
      id: 'right-column',
      flexDirection: 'column',
      width: '25%',
      height: '100%',
      position: 'relative',
    });

    const resourcesPanel = Box({
      id: 'resources-panel',
      width: '100%',
      height: '40%',
      backgroundColor: '#0d1117',
      borderStyle: 'double',
      borderColor: '#d29922',
      title: ' Resources ',
      position: 'relative',
    });

    const resourcesText = Text({
      id: 'resources-text',
      content: 'Loading resources...',
      fg: '#ffffff',
      position: 'absolute',
      left: 1,
      top: 1,
    });

    resourcesPanel.add(resourcesText);

    const workersPanel = Box({
      id: 'workers-panel',
      width: '100%',
      height: '30%',
      backgroundColor: '#0d1117',
      borderStyle: 'double',
      borderColor: '#58a6ff',
      title: ' Workers ',
      position: 'relative',
    });

    const workersHeader = Text({
      id: 'workers-header',
      content: '#  Worker    Status       Task',
      fg: '#8b949e',
      position: 'absolute',
      left: 1,
      top: 1,
    });

    workersPanel.add(workersHeader);

    const workersList = Box({
      id: 'workers-list',
      flexDirection: 'column',
      width: '100%',
      height: '100%',
      position: 'absolute',
      top: 3,
      left: 0,
    });

    workersPanel.add(workersList);

    // Ralph Live panel - shows project, model settings, quick actions
    const ralphPanel = Box({
      id: 'ralph-panel',
      width: '100%',
      height: '30%',
      backgroundColor: '#0f0a1a',
      borderStyle: 'double',
      borderColor: '#a855f7',
      title: ' Ralph Live ',
      position: 'relative',
    });

    const ralphText = Text({
      id: 'ralph-text',
      content: 'Loading Ralph Live...',
      fg: '#e9d5ff',
      position: 'absolute',
      left: 1,
      top: 1,
    });

    ralphPanel.add(ralphText);

    const ralphList = Box({
      id: 'ralph-list',
      flexDirection: 'column',
      width: '100%',
      height: '100%',
      position: 'absolute',
      top: 1,
      left: 0,
    });

    ralphPanel.add(ralphList);

    rightColumn.add(resourcesPanel);
    rightColumn.add(workersPanel);
    rightColumn.add(ralphPanel);

    middleContainer.add(actionsPanel);
    middleContainer.add(tasksPanel);
    middleContainer.add(rightColumn);

    const consolePanel = Box({
      id: 'console-panel',
      width: '100%',
      height: '35%',
      backgroundColor: '#0a0c10',
      borderStyle: 'double',
      borderColor: '#a371f7',
      title: ' Console Log ',
      position: 'relative',
    });

    const consoleHeader = Text({
      id: 'console-header',
      content: 'Time        Worker    Message',
      fg: '#8b949e',
      position: 'absolute',
      left: 1,
      top: 1,
    });

    consolePanel.add(consoleHeader);

    const consoleList = Box({
      id: 'console-list',
      flexDirection: 'column',
      width: '100%',
      height: '100%',
      position: 'absolute',
      top: 3,
      left: 0,
    });

    consolePanel.add(consoleList);

    mainContainer.add(middleContainer);
    mainContainer.add(consolePanel);

    this.renderer.root.add(mainContainer);
  }

  private startRefreshLoop() {
    this.refreshData();
    this.refreshTimer = setInterval(() => {
      this.refreshData();
    }, this.refreshInterval);
  }

  private refreshData() {
    try {
      const run = this.db.getCurrentRun();
      
      if (run) {
        this.currentRunId = run.run_id;
        this.updateHeader(run);
        this.updateWorkers(run.run_id);
        this.updateTasks(run.run_id);
        this.updateResources(run.run_id);
        this.updateConsole(run.run_id);
        this.updateRalphLive(run.run_id);
      } else {
        this.updateHeaderNoRun();
        this.clearLists();
        this.clearConsole();
        this.updateRalphLive(null);
      }
    } catch (error) {
      console.error('Error refreshing data:', error);
      const statusText = this.renderer.root.findDescendantById('status');
      if (statusText) {
        (statusText as any).content = 'Error loading data';
      }
    }
  }

  private updateHeader(run: any) {
    const completedPercent = run.total_tasks > 0 
      ? ((run.completed_tasks / run.total_tasks) * 100).toFixed(1)
      : '0.0';
    
    const statusText = this.renderer.root.findDescendantById('status');
    if (statusText) {
      (statusText as any).content = `[${run.status.toUpperCase()}] Run: ${run.run_id} | Workers: ${run.worker_count} | Progress: ${run.completed_tasks}/${run.total_tasks} (${completedPercent}%)`;
    }
  }

  private updateHeaderNoRun() {
    const statusText = this.renderer.root.findDescendantById('status');
    if (statusText) {
      (statusText as any).content = '[NO ACTIVE RUN] Press "r" to refresh or "q" to quit';
    }
  }

  private updateWorkers(runId: string) {
    const workers = this.db.getWorkersByRun(runId);
    const workersList = this.renderer.root.findDescendantById('workers-list');
    if (!workersList) return;

    // Build mapping of tasks by id for quick lookup
    const allTasks = this.db.getTasksByRun(runId);
    const taskById = new Map<number, any>();
    for (const t of allTasks) taskById.set(t.id, t);

    // Build stable worker lines (include branch and task first line). We'll
    // render a window slice to avoid modifying nodes while scrolling.
    const workerLines: Array<{ content: string; fg: string }> = [];
    workers.forEach((worker, index) => {
      const statusColor = this.getStatusColor(worker.status);
      const statusIcon = this.getStatusIcon(worker.status);
      const assignedTaskId = worker.current_task_id ?? (allTasks.find(t => t.worker_id === worker.id)?.id ?? null);
      const taskName = assignedTaskId ? (String(taskById.get(assignedTaskId)?.task_text || '').split('\n')[0] || '') : '';
      const branch = worker.branch_name ? ` ${worker.branch_name}` : '';
      const parts = [`${index + 1}. W${worker.worker_num.toString().padStart(2)}`, statusIcon, worker.status];
      if (assignedTaskId) parts.push(`[T#${assignedTaskId}]`);
      if (branch) parts.push(branch);
      if (taskName) parts.push('-', taskName);
      workerLines.push({ content: parts.join(' '), fg: statusColor });
    });

    // Update pane count for scrolling bounds
    this.paneCounts.workers = workerLines.length;

    // Clear and render visible window
    while (workersList.getChildrenCount() > 0) {
      const child = workersList.getChildren()[0];
      workersList.remove(child.id);
    }
    const wOff = this.paneOffsets.workers || 0;
    const wWindow = workerLines.slice(wOff, wOff + this.pageSize);
    wWindow.forEach((l, idx) => {
      workersList.add(Text({ id: `worker-line-${idx}-${wOff}`, content: l.content, fg: l.fg, position: 'relative' }));
    });

    // Actions pane: show recent log lines (activity stream). Do not include
    // branch/path here — leave that for the workers pane.
    const actionsList = this.renderer.root.findDescendantById('actions-list');
    if (actionsList) {
      while (actionsList.getChildrenCount() > 0) {
        const child = actionsList.getChildren()[0];
        actionsList.remove(child.id);
      }

      const logs = this.db.getRecentLogs(runId, 100); // reduce how many recent logs we fetch
      const actionLines: Array<{ content: string; fg: string }> = [];
      for (const log of logs) {
        const clean = String(log.log_line).replace(/\x1b\[[0-9;]*m/g, '').trim();
        if (!clean) continue;
        actionLines.push({ content: `W${log.worker_num.padStart(2)}  ${clean}`, fg: this.getLogColor(clean) });
      }

      // Track total lines for actions pane and render visible window
      this.paneCounts.actions = actionLines.length;
      const aOff = this.paneOffsets.actions || 0;
      const aWindow = actionLines.slice(aOff, aOff + this.pageSize);
      aWindow.forEach((l, idx) => {
        actionsList.add(Text({ id: `action-line-${idx}-${aOff}`, content: l.content, fg: l.fg, position: 'relative' }));
      });
    }
  }

  private updateTasks(runId: string) {
    const tasks = this.db.getTasksByRun(runId);
    const tasksList = this.renderer.root.findDescendantById('tasks-list');
    
    if (!tasksList) return;

    // Build flattened lines for tasks (main + wrapped lines) to support scrolling
    const taskLines: Array<{ content: string; fg: string }> = [];
    for (const task of tasks) {
      const statusColor = this.getStatusColor(task.status);
      const firstLine = task.task_text.split('\n')[0].substring(0, 80);
      taskLines.push({ content: `${task.id.toString().padStart(2)}. ${task.status.padEnd(12)} ${firstLine}`, fg: statusColor });

      const remaining = task.task_text.length > 80 ? task.task_text.substring(80) : '';
      if (remaining) {
        const wrapped = remaining.match(/.{1,80}(?:\s|$)|\S+/g) || [];
        wrapped.forEach((line) => {
          taskLines.push({ content: `    ${line.trim()}`, fg: '#8b949e' });
        });
      }
    }

    // Update pane count and render the visible window
    this.paneCounts.tasks = taskLines.length;
    const tOff = this.paneOffsets.tasks || 0;
    const tWindow = taskLines.slice(tOff, tOff + this.pageSize);

    while (tasksList.getChildrenCount() > 0) {
      const child = tasksList.getChildren()[0];
      tasksList.remove(child.id);
    }
    tWindow.forEach((l, idx) => {
      tasksList.add(Text({ id: `task-line-${idx}-${tOff}`, content: l.content, fg: l.fg, position: 'relative' }));
    });
  }

  private updateResources(runId: string) {
    const costs = this.db.getTotalCosts(runId);
    const stats = this.db.getTaskStats(runId);
    const recentCosts = this.db.getRecentTaskCosts(runId, 5);
    
    const resourceText = [
      `╔══════════════════════╗`,
      `║   RESOURCE SUMMARY   ║`,
      `╠══════════════════════╣`,
      `║                      ║`,
      `║ Total Cost: $${costs.total_cost.toFixed(2).padStart(8)}║`,
      `║                      ║`,
      `║ Prompt Tokens:        ║`,
      `║ ${costs.total_prompt_tokens.toString().padStart(16)}║`,
      `║                      ║`,
      `║ Completion Tokens:    ║`,
      `║ ${costs.total_completion_tokens.toString().padStart(16)}║`,
      `║                      ║`,
      `╠══════════════════════╣`,
      `║   TASK STATUS         ║`,
      `╠══════════════════════╣`,
      `║ Pending: ${stats.pending.toString().padStart(10)}║`,
      `║ In Progress: ${stats.in_progress.toString().padStart(5)}║`,
      `║ Completed: ${stats.completed.toString().padStart(7)}║`,
      `║ Failed: ${stats.failed.toString().padStart(10)}║`,
      `╠══════════════════════╣`,
      `║   RECENT COSTS        ║`,
      `╠══════════════════════╣`,
    ];

    recentCosts.forEach((cost) => {
      resourceText.push(`║ $${cost.cost.toFixed(4).padStart(6)} T:${cost.task_id.toString().padStart(4)}║`);
    });

    resourceText.push(`╚══════════════════════╝`);

    const resourcesText = this.renderer.root.findDescendantById('resources-text');
    if (resourcesText) {
      (resourcesText as any).content = resourceText.join('\n');
      (resourcesText as any).fg = '#c9d1d9';
    }
  }

  private updateRalphLive(runId: string | null) {
    const ralphList = this.renderer.root.findDescendantById('ralph-list');
    if (!ralphList) return;

    // Clear existing content
    while (ralphList.getChildrenCount() > 0) {
      const child = ralphList.getChildren()[0];
      ralphList.remove(child.id);
    }

    // Try to load ralph-live state from environment or files
    this.loadRalphLiveState();

    const lines: Array<{ content: string; fg: string }> = [];

    // Project info
    if (this.ralphLiveState.currentProject) {
      lines.push({ content: `Project: ${this.ralphLiveState.currentProject}`, fg: '#a855f7' });
    } else {
      lines.push({ content: 'Project: (none)', fg: '#6b7280' });
    }

    // Workdir
    if (this.ralphLiveState.workdir) {
      const shortPath = this.ralphLiveState.workdir.length > 25 
        ? '...' + this.ralphLiveState.workdir.slice(-22) 
        : this.ralphLiveState.workdir;
      lines.push({ content: `Workdir: ${shortPath}`, fg: '#9ca3af' });
    }

    // DevPlan
    if (this.ralphLiveState.devplanPath) {
      const devplanName = this.ralphLiveState.devplanPath.split('/').pop() || 'devplan.md';
      lines.push({ content: `DevPlan: ${devplanName}`, fg: '#c084fc' });
    }

    lines.push({ content: '', fg: '#ffffff' }); // Spacer

    // Model settings
    const provider = this.ralphLiveState.provider || process.env.RALPH_LLM_PROVIDER || 'default';
    const model = this.ralphLiveState.model || process.env.RALPH_LLM_MODEL || 'default';
    lines.push({ content: `Provider: ${provider}`, fg: '#818cf8' });
    lines.push({ content: `Model: ${model.split('/').pop() || model}`, fg: '#818cf8' });

    // Swarm-specific settings if different
    const swarmProvider = this.ralphLiveState.swarmProvider || process.env.SWARM_PROVIDER;
    const swarmModel = this.ralphLiveState.swarmModel || process.env.SWARM_MODEL;
    if (swarmProvider || swarmModel) {
      lines.push({ content: '', fg: '#ffffff' }); // Spacer
      lines.push({ content: `Swarm Provider: ${swarmProvider || 'agent'}`, fg: '#f472b6' });
      lines.push({ content: `Swarm Model: ${(swarmModel || 'agent').split('/').pop()}`, fg: '#f472b6' });
    }

    lines.push({ content: '', fg: '#ffffff' }); // Spacer

    // Quick commands hint
    lines.push({ content: '─────────────────', fg: '#4b5563' });
    lines.push({ content: 'Tab: cycle panes', fg: '#6b7280' });
    lines.push({ content: 'q: quit  r: refresh', fg: '#6b7280' });
    lines.push({ content: 'p: pause polling', fg: '#6b7280' });

    // Focused pane indicator
    if (this.focusedPane === 'ralph') {
      lines.push({ content: '', fg: '#ffffff' });
      lines.push({ content: '● FOCUSED', fg: '#a855f7' });
    }

    // Update pane count
    this.paneCounts.ralph = lines.length;
    const rOff = this.paneOffsets.ralph || 0;
    const rWindow = lines.slice(rOff, rOff + this.pageSize);

    rWindow.forEach((l, idx) => {
      ralphList.add(Text({ id: `ralph-line-${idx}-${rOff}`, content: ` ${l.content}`, fg: l.fg, position: 'relative' }));
    });
  }

  private loadRalphLiveState() {
    // Try to read from environment variables or state files
    const homeDir = process.env.HOME || '/home/mojo';
    const projectsDir = process.env.SWARM_PROJECTS_BASE || `${homeDir}/projects`;
    const currentProjectFile = `${projectsDir}/current`;

    try {
      // Read current project name
      const fs = require('fs');
      if (fs.existsSync(currentProjectFile)) {
        const projectName = fs.readFileSync(currentProjectFile, 'utf-8').trim();
        this.ralphLiveState.currentProject = projectName;

        // Try to load project.env
        const projectEnvPath = `${projectsDir}/${projectName}/project.env`;
        if (fs.existsSync(projectEnvPath)) {
          const envContent = fs.readFileSync(projectEnvPath, 'utf-8');
          const lines = envContent.split('\n');
          for (const line of lines) {
            const match = line.match(/^(\w+)="?([^"]*)"?$/);
            if (match) {
              const [, key, value] = match;
              if (key === 'WORKDIR') this.ralphLiveState.workdir = value;
              if (key === 'DEVPLAN_PATH') this.ralphLiveState.devplanPath = value;
            }
          }
        }
      }
    } catch (e) {
      // Ignore errors reading state files
    }

    // Also check environment variables
    this.ralphLiveState.provider = process.env.RALPH_LLM_PROVIDER || process.env.PROVIDER || '';
    this.ralphLiveState.model = process.env.RALPH_LLM_MODEL || process.env.MODEL || '';
    this.ralphLiveState.swarmProvider = process.env.SWARM_PROVIDER || '';
    this.ralphLiveState.swarmModel = process.env.SWARM_MODEL || '';
  }

  private clearLists() {
    const workersList = this.renderer.root.findDescendantById('workers-list');
    const tasksList = this.renderer.root.findDescendantById('tasks-list');
    const ralphList = this.renderer.root.findDescendantById('ralph-list');
    
    if (workersList) {
      while (workersList.getChildrenCount() > 0) {
        const child = workersList.getChildren()[0];
        workersList.remove(child.id);
      }
    }
    if (tasksList) {
      while (tasksList.getChildrenCount() > 0) {
        const child = tasksList.getChildren()[0];
        tasksList.remove(child.id);
      }
    }
    if (ralphList) {
      while (ralphList.getChildrenCount() > 0) {
        const child = ralphList.getChildren()[0];
        ralphList.remove(child.id);
      }
    }
    
    const resourcesText = this.renderer.root.findDescendantById('resources-text');
    if (resourcesText) {
      (resourcesText as any).content = 'No active run';
    }
  }

  private updateConsole(runId: string) {
    const logs = this.db.getRecentLogs(runId, 15);
    const consoleList = this.renderer.root.findDescendantById('console-list');
    
    if (!consoleList) {
      return;
    }

    this.logLines = logs;

    // Build console lines and support scrolling window
    const consoleLines: Array<{ content: string; fg: string }> = [];
    for (const log of logs) {
      const cleanLogLine = log.log_line
        .replace(/\x1b\[[0-9;]*m/g, '')
        .replace(/\[\d+m/g, '')
        .trim();
      if (cleanLogLine.length === 0) continue;
      const truncatedLog = cleanLogLine.length > 80 ? cleanLogLine.substring(0, 77) + '...' : cleanLogLine;
      consoleLines.push({ content: `W${log.worker_num.padStart(2)}  ${truncatedLog}`, fg: this.getLogColor(cleanLogLine) });
    }

    this.paneCounts.console = consoleLines.length;
    const cOff = this.paneOffsets.console || 0;
    const cWindow = consoleLines.slice(cOff, cOff + this.pageSize);

    while (consoleList.getChildrenCount() > 0) {
      const child = consoleList.getChildren()[0];
      consoleList.remove(child.id);
    }
    cWindow.forEach((l, idx) => {
      consoleList.add(Text({ id: `console-line-${idx}-${cOff}`, content: l.content, fg: l.fg, position: 'relative' }));
    });
  }

  private clearConsole() {
    const consoleList = this.renderer.root.findDescendantById('console-list');
    
    if (consoleList) {
      while (consoleList.getChildrenCount() > 0) {
        const child = consoleList.getChildren()[0];
        consoleList.remove(child.id);
      }
    }
    this.logLines = [];
  }

  private getLogColor(logLine: string): string {
    const lowerLine = logLine.toLowerCase();
    if (lowerLine.includes('error') || lowerLine.includes('failed')) {
      return '#da3633';
    } else if (lowerLine.includes('warning') || lowerLine.includes('warn')) {
      return '#d29922';
    } else if (lowerLine.includes('worker') && lowerLine.includes('executing')) {
      return '#238636';
    } else if (lowerLine.includes('debug')) {
      return '#8b949e';
    }
    return '#c9d1d9';
  }

  private getStatusColor(status: string): string {
    const colors: Record<string, string> = {
      'idle': '#d29922',
      'working': '#238636',
      'stopped': '#8b949e',
      'error': '#da3633',
      'pending': '#d29922',
      'in_progress': '#238636',
      'completed': '#58a6ff',
      'failed': '#da3633',
    };
    return colors[status] || '#c9d1d9';
  }

  private getStatusIcon(status: string): string {
    const icons: Record<string, string> = {
      'idle': '○',
      'working': '●',
      'stopped': '■',
      'error': '✗',
      'pending': '○',
      'in_progress': '●',
      'completed': '✓',
      'failed': '✗',
    };
    return icons[status] || '?';
  }

  private cleanup() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
    }
    try {
      this.db.close();
    } catch (e) {
      // Ignore cleanup errors
    }
    try {
      this.renderer.stop();
    } catch (e) {
      // Ignore cleanup errors
    }
  }
}
