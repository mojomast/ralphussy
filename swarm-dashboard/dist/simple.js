import { createSwarmDatabase } from './database-bun.js';
const COLORS = {
    reset: '\x1b[0m',
    bold: '\x1b[1m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    gray: '\x1b[90m',
    cyan: '\x1b[36m',
};
function color(text, colorCode) {
    return `${colorCode}${text}${COLORS.reset}`;
}
function clearScreen() {
    console.log('\x1b[2J\x1b[H');
}
function getStatusColor(status) {
    const colorMap = {
        'idle': COLORS.yellow,
        'working': COLORS.green,
        'stopped': COLORS.gray,
        'error': COLORS.red,
        'pending': COLORS.yellow,
        'in_progress': COLORS.green,
        'completed': COLORS.blue,
        'failed': COLORS.red,
    };
    return colorMap[status] || COLORS.gray;
}
function getStatusIcon(status) {
    const iconMap = {
        'idle': '○',
        'working': '●',
        'stopped': '■',
        'error': '✗',
        'pending': '○',
        'in_progress': '●',
        'completed': '✓',
        'failed': '✗',
    };
    return iconMap[status] || '?';
}
async function main() {
    const db = createSwarmDatabase();
    console.log(color('\n🐝 Swarm Dashboard (Simple CLI Mode)', COLORS.bold));
    console.log(color('Press Ctrl+C to exit\n', COLORS.gray));
    let running = true;
    // Handle graceful exit
    process.on('SIGINT', () => {
        running = false;
        console.log('\n' + color('Exiting...', COLORS.gray));
        db.close();
        process.exit(0);
    });
    let iteration = 0;
    while (running) {
        clearScreen();
        const run = db.getCurrentRun();
        if (!run) {
            console.log(color('No active swarm run found', COLORS.yellow));
            console.log(color('Start a swarm run with Ralph to see data', COLORS.gray));
        }
        else {
            const completedPercent = run.total_tasks > 0
                ? ((run.completed_tasks / run.total_tasks) * 100).toFixed(1)
                : '0.0';
            console.log(color('='.repeat(60), COLORS.gray));
            console.log(color(`📊 Run: ${run.run_id}`, COLORS.bold));
            console.log(color('='.repeat(60), COLORS.gray));
            console.log('');
            console.log(`  Status: ${color(run.status.toUpperCase(), getStatusColor(run.status))}`);
            console.log(`  Workers: ${run.worker_count}`);
            console.log(`  Progress: ${run.completed_tasks}/${run.total_tasks} (${color(completedPercent + '%', COLORS.green)})`);
            console.log('');
            console.log(color('='.repeat(60), COLORS.gray));
            console.log(color('👷 Workers', COLORS.bold));
            console.log(color('='.repeat(60), COLORS.gray));
            const workers = db.getWorkersByRun(run.run_id);
            workers.forEach((worker, index) => {
                const statusColor = getStatusColor(worker.status);
                const statusIcon = getStatusIcon(worker.status);
                const taskInfo = worker.current_task_id ? `Task #${worker.current_task_id}` : 'Idle';
                console.log(`  ${index + 1}. Worker-${worker.worker_num.toString().padStart(2)}  ${color(statusIcon + worker.status.padEnd(10), statusColor)}  ${taskInfo}`);
            });
            console.log('');
            console.log(color('='.repeat(60), COLORS.gray));
            console.log(color('📝 Tasks (Recent)', COLORS.bold));
            console.log(color('='.repeat(60), COLORS.gray));
            const tasks = db.getTasksByRun(run.run_id).slice(0, 10);
            tasks.forEach((task) => {
                const statusColor = getStatusColor(task.status);
                const truncatedText = task.task_text.length > 50
                    ? task.task_text.substring(0, 47) + '...'
                    : task.task_text;
                console.log(`  ${task.id.toString().padStart(2)}. ${color(task.status.padEnd(12), statusColor)} ${truncatedText}`);
            });
            console.log('');
            console.log(color('='.repeat(60), COLORS.gray));
            console.log(color('💰 Resources', COLORS.bold));
            console.log(color('='.repeat(60), COLORS.gray));
            const costs = db.getTotalCosts(run.run_id);
            const stats = db.getTaskStats(run.run_id);
            console.log(`  Total Cost: ${color('$' + costs.total_cost.toFixed(2), COLORS.green)}`);
            console.log(`  Prompt Tokens: ${costs.total_prompt_tokens.toLocaleString()}`);
            console.log(`  Completion Tokens: ${costs.total_completion_tokens.toLocaleString()}`);
            console.log('');
            console.log(`  Pending: ${stats.pending}`);
            console.log(`  In Progress: ${color(stats.in_progress.toString(), COLORS.yellow)}`);
            console.log(`  Completed: ${color(stats.completed.toString(), COLORS.green)}`);
            console.log(`  Failed: ${color(stats.failed.toString(), stats.failed > 0 ? COLORS.red : COLORS.gray)}`);
        }
        console.log('');
        console.log(color('─'.repeat(60), COLORS.gray));
        console.log(color(`Update: ${new Date().toLocaleTimeString()} | Refreshing in 2s...`, COLORS.cyan));
        console.log(color('─'.repeat(60), COLORS.gray));
        iteration++;
        // Wait for 2 seconds
        await new Promise(resolve => setTimeout(resolve, 2000));
    }
}
main().catch((error) => {
    console.error('Error:', error);
    process.exit(1);
});
//# sourceMappingURL=simple.js.map