import { createCliRenderer, Box, Text, type BoxOptions, type TextOptions, ConsolePosition } from '@opentui/core';
import { createSwarmDatabase } from './database-bun.js';

export class SwarmDashboard {
  private renderer!: Awaited<ReturnType<typeof createCliRenderer>>;
  private db!: ReturnType<typeof createSwarmDatabase>;
  private refreshInterval: number = 2000;
  private refreshTimer: NodeJS.Timeout | null = null;
  private currentRunId: string | null = null;
  private lastLogTimestamp: number = 0;
  private logLines: Array<{ worker_num: string; log_line: string }> = [];

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

      this.db = createSwarmDatabase();
      
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
      if (key.ctrl && key.name === 'c') {
        this.cleanup();
        process.exit(0);
      } else if (key.name === 'q') {
        this.cleanup();
        process.exit(0);
      } else if (key.name === 'r') {
        this.refreshData();
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

    const middleContainer = Box({
      id: 'middle',
      flexDirection: 'row',
      width: '100%',
      height: '60%',
      position: 'relative',
    });

    const workersPanel = Box({
      id: 'workers-panel',
      width: '40%',
      height: '100%',
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

    const tasksPanel = Box({
      id: 'tasks-panel',
      width: '35%',
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

    const resourcesPanel = Box({
      id: 'resources-panel',
      width: '25%',
      height: '100%',
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

    middleContainer.add(workersPanel);
    middleContainer.add(tasksPanel);
    middleContainer.add(resourcesPanel);

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
      } else {
        this.updateHeaderNoRun();
        this.clearLists();
        this.clearConsole();
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

    while (workersList.getChildrenCount() > 0) {
      const child = workersList.getChildren()[0];
      workersList.remove(child.id);
    }

    workers.forEach((worker, index) => {
      const statusColor = this.getStatusColor(worker.status);
      const statusIcon = this.getStatusIcon(worker.status);
      const taskInfo = worker.current_task_id ? `Task #${worker.current_task_id}` : 'Idle';
      
      const workerText = Text({
        id: `worker-${worker.id}`,
        content: `${index + 1}.  Worker-${worker.worker_num.toString().padStart(2)}  ${statusIcon}${worker.status.padEnd(10)}  ${taskInfo}`,
        fg: statusColor,
        position: 'relative',
      });

      workersList.add(workerText);
    });
  }

  private updateTasks(runId: string) {
    const tasks = this.db.getTasksByRun(runId).slice(0, 20);
    const tasksList = this.renderer.root.findDescendantById('tasks-list');
    
    if (!tasksList) return;

    while (tasksList.getChildrenCount() > 0) {
      const child = tasksList.getChildren()[0];
      tasksList.remove(child.id);
    }

    tasks.forEach((task) => {
      const statusColor = this.getStatusColor(task.status);
      const truncatedText = task.task_text.length > 40 
        ? task.task_text.substring(0, 37) + '...'
        : task.task_text;
      
      const taskText = Text({
        id: `task-${task.id}`,
        content: `${task.id.toString().padStart(2)}.  ${task.status.padEnd(8)}  ${truncatedText}`,
        fg: statusColor,
        position: 'relative',
      });

      tasksList.add(taskText);
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

  private clearLists() {
    const workersList = this.renderer.root.findDescendantById('workers-list');
    const tasksList = this.renderer.root.findDescendantById('tasks-list');
    
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

    while (consoleList.getChildrenCount() > 0) {
      const child = consoleList.getChildren()[0];
      consoleList.remove(child.id);
    }

    for (const log of logs) {
      const cleanLogLine = log.log_line
        .replace(/\x1b\[[0-9;]*m/g, '')
        .replace(/\[\d+m/g, '')
        .trim();
      
      if (cleanLogLine.length === 0) continue;

      const truncatedLog = cleanLogLine.length > 80 
        ? cleanLogLine.substring(0, 77) + '...'
        : cleanLogLine;

      const logText = Text({
        id: `console-${log.worker_num}-${Math.random().toString(36).substring(7)}`,
        content: `W${log.worker_num.padStart(2)}  ${truncatedLog}`,
        fg: this.getLogColor(cleanLogLine),
        position: 'relative',
      });

      consoleList.add(logText);
    }
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
