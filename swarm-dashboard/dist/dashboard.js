import { createCliRenderer, Box, Text, ConsolePosition } from '@opentui/core';
import { createSwarmDatabase } from './database-bun.js';
export class SwarmDashboard {
    renderer;
    db;
    refreshInterval = 2000;
    refreshTimer = null;
    currentRunId = null;
    lastLogTimestamp = 0;
    logLines = [];
    // Scrolling / focus state for panes
    paneOffsets = { actions: 0, tasks: 0, workers: 0, console: 0 };
    focusedPane = 'tasks';
    pageSize = 20;
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
        }
        catch (error) {
            console.error('Failed to initialize dashboard:', error);
            process.exit(1);
        }
        this.setupKeyboardHandlers();
        this.createLayout();
        this.startRefreshLoop();
        this.renderer.start();
    }
    setupKeyboardHandlers() {
        this.renderer.keyInput.on('keypress', (key) => {
            if (key.ctrl && key.name === 'c') {
                this.cleanup();
                process.exit(0);
            }
            else if (key.name === 'q') {
                this.cleanup();
                process.exit(0);
            }
            else if (key.name === 'r') {
                this.refreshData();
            }
            else if (key.name === 'tab') {
                // Cycle focus: tasks -> actions -> workers -> console
                const order = ['tasks', 'actions', 'workers', 'console'];
                const idx = order.indexOf(this.focusedPane);
                this.focusedPane = order[(idx + 1) % order.length];
                this.refreshData();
            }
            else if (key.name === 'up' || key.name === 'down' || key.name === 'pageup' || key.name === 'pagedown') {
                // Scroll the focused pane
                let delta = 0;
                if (key.name === 'up')
                    delta = -1;
                else if (key.name === 'down')
                    delta = 1;
                else if (key.name === 'pageup')
                    delta = -Math.max(1, Math.floor(this.pageSize * 0.8));
                else if (key.name === 'pagedown')
                    delta = Math.max(1, Math.floor(this.pageSize * 0.8));
                const cur = this.paneOffsets[this.focusedPane] || 0;
                let next = cur + delta;
                if (next < 0)
                    next = 0;
                this.paneOffsets[this.focusedPane] = next;
                this.refreshData();
            }
        });
    }
    createLayout() {
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
            height: '60%',
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
            height: '40%',
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
        rightColumn.add(resourcesPanel);
        rightColumn.add(workersPanel);
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
    startRefreshLoop() {
        this.refreshData();
        this.refreshTimer = setInterval(() => {
            this.refreshData();
        }, this.refreshInterval);
    }
    refreshData() {
        try {
            const run = this.db.getCurrentRun();
            if (run) {
                this.currentRunId = run.run_id;
                this.updateHeader(run);
                this.updateWorkers(run.run_id);
                this.updateTasks(run.run_id);
                this.updateResources(run.run_id);
                this.updateConsole(run.run_id);
            }
            else {
                this.updateHeaderNoRun();
                this.clearLists();
                this.clearConsole();
            }
        }
        catch (error) {
            console.error('Error refreshing data:', error);
            const statusText = this.renderer.root.findDescendantById('status');
            if (statusText) {
                statusText.content = 'Error loading data';
            }
        }
    }
    updateHeader(run) {
        const completedPercent = run.total_tasks > 0
            ? ((run.completed_tasks / run.total_tasks) * 100).toFixed(1)
            : '0.0';
        const statusText = this.renderer.root.findDescendantById('status');
        if (statusText) {
            statusText.content = `[${run.status.toUpperCase()}] Run: ${run.run_id} | Workers: ${run.worker_count} | Progress: ${run.completed_tasks}/${run.total_tasks} (${completedPercent}%)`;
        }
    }
    updateHeaderNoRun() {
        const statusText = this.renderer.root.findDescendantById('status');
        if (statusText) {
            statusText.content = '[NO ACTIVE RUN] Press "r" to refresh or "q" to quit';
        }
    }
    updateWorkers(runId) {
        const workers = this.db.getWorkersByRun(runId);
        const workersList = this.renderer.root.findDescendantById('workers-list');
        if (!workersList)
            return;
        // Build mapping of tasks by id for quick lookup
        const allTasks = this.db.getTasksByRun(runId);
        const taskById = new Map();
        const taskByWorkerId = new Map();
        for (const t of allTasks) {
            taskById.set(t.id, t);
            if (t.worker_id !== null) {
                taskByWorkerId.set(t.worker_id, t);
            }
        }
        // Build stable worker lines (include branch and task first line). We'll
        // render a window slice to avoid modifying nodes while scrolling.
        const workerLines = [];
        workers.forEach((worker, index) => {
            const statusColor = this.getStatusColor(worker.status);
            const statusIcon = this.getStatusIcon(worker.status);
            const assignedTaskId = worker.current_task_id ?? (taskByWorkerId.get(worker.id)?.id ?? null);
            const taskName = assignedTaskId ? (String(taskById.get(assignedTaskId)?.task_text || '').split('\n')[0] || '') : '';
            const branch = worker.branch_name ? ` ${worker.branch_name}` : '';
            const parts = [`${index + 1}. W${worker.worker_num.toString().padStart(2)}`, statusIcon, worker.status];
            if (assignedTaskId)
                parts.push(`[T#${assignedTaskId}]`);
            if (branch)
                parts.push(branch);
            if (taskName)
                parts.push('-', taskName);
            workerLines.push({ content: parts.join(' '), fg: statusColor });
        });
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
            const logs = this.db.getRecentLogs(runId, 200);
            const actionLines = [];
            for (const log of logs) {
                const clean = String(log.log_line).replace(/\x1b\[[0-9;]*m/g, '').trim();
                if (!clean)
                    continue;
                actionLines.push({ content: `W${log.worker_num.padStart(2)}  ${clean}`, fg: this.getLogColor(clean) });
            }
            const aOff = this.paneOffsets.actions || 0;
            const aWindow = actionLines.slice(aOff, aOff + this.pageSize);
            aWindow.forEach((l, idx) => {
                actionsList.add(Text({ id: `action-line-${idx}-${aOff}`, content: l.content, fg: l.fg, position: 'relative' }));
            });
        }
    }
    updateTasks(runId) {
        // Show all tasks (pending/in_progress first) and allow scrolling in the
        // TUI by not truncating here. We'll fetch and order tasks so the pane can
        // render many entries.
        const tasks = this.db.getTasksByRun(runId);
        const tasksList = this.renderer.root.findDescendantById('tasks-list');
        if (!tasksList)
            return;
        while (tasksList.getChildrenCount() > 0) {
            const child = tasksList.getChildren()[0];
            tasksList.remove(child.id);
        }
        tasks.forEach((task) => {
            const statusColor = this.getStatusColor(task.status);
            // Word-wrap the task text to avoid overflowing the pane. Keep an
            // abbreviated first line for quick scanning.
            const firstLine = task.task_text.split('\n')[0].substring(0, 80);
            const taskText = Text({
                id: `task-${task.id}`,
                content: `${task.id.toString().padStart(2)}. ${task.status.padEnd(12)} ${firstLine}`,
                fg: statusColor,
                position: 'relative',
            });
            tasksList.add(taskText);
            // Add wrapped additional lines as separate Text nodes so panes can scroll
            const remaining = task.task_text.length > 80 ? task.task_text.substring(80) : '';
            if (remaining) {
                const wrapped = remaining.match(/.{1,80}(?:\s|$)|\S+/g) || [];
                wrapped.forEach((line, idx) => {
                    const extra = Text({
                        id: `task-${task.id}-extra-${idx}`,
                        content: `    ${line.trim()}`,
                        fg: '#8b949e',
                        position: 'relative',
                    });
                    tasksList.add(extra);
                });
            }
        });
        // Apply scrolling for tasks pane
        const tOff = this.paneOffsets.tasks || 0;
        for (let i = 0; i < tOff; i++) {
            if (tasksList.getChildrenCount() > 0) {
                const child = tasksList.getChildren()[0];
                tasksList.remove(child.id);
            }
        }
    }
    updateResources(runId) {
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
            resourcesText.content = resourceText.join('\n');
            resourcesText.fg = '#c9d1d9';
        }
    }
    clearLists() {
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
            resourcesText.content = 'No active run';
        }
    }
    updateConsole(runId) {
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
            if (cleanLogLine.length === 0)
                continue;
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
        // Apply scrolling for console pane
        const cOff = this.paneOffsets.console || 0;
        for (let i = 0; i < cOff; i++) {
            if (consoleList.getChildrenCount() > 0) {
                const child = consoleList.getChildren()[0];
                consoleList.remove(child.id);
            }
        }
    }
    clearConsole() {
        const consoleList = this.renderer.root.findDescendantById('console-list');
        if (consoleList) {
            while (consoleList.getChildrenCount() > 0) {
                const child = consoleList.getChildren()[0];
                consoleList.remove(child.id);
            }
        }
        this.logLines = [];
    }
    getLogColor(logLine) {
        const lowerLine = logLine.toLowerCase();
        if (lowerLine.includes('error') || lowerLine.includes('failed')) {
            return '#da3633';
        }
        else if (lowerLine.includes('warning') || lowerLine.includes('warn')) {
            return '#d29922';
        }
        else if (lowerLine.includes('worker') && lowerLine.includes('executing')) {
            return '#238636';
        }
        else if (lowerLine.includes('debug')) {
            return '#8b949e';
        }
        return '#c9d1d9';
    }
    getStatusColor(status) {
        const colors = {
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
    getStatusIcon(status) {
        const icons = {
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
    cleanup() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
        }
        try {
            this.db.close();
        }
        catch (e) {
            // Ignore cleanup errors
        }
        try {
            this.renderer.stop();
        }
        catch (e) {
            // Ignore cleanup errors
        }
    }
}
//# sourceMappingURL=dashboard.js.map