export declare class SwarmDashboard {
    private renderer;
    private db;
    private refreshInterval;
    private refreshTimer;
    private currentRunId;
    private lastLogTimestamp;
    private logLines;
    init(): Promise<void>;
    private setupKeyboardHandlers;
    private createLayout;
    private startRefreshLoop;
    private refreshData;
    private updateHeader;
    private updateHeaderNoRun;
    private updateWorkers;
    private updateTasks;
    private updateResources;
    private clearLists;
    private updateConsole;
    private clearConsole;
    private getLogColor;
    private getStatusColor;
    private getStatusIcon;
    private cleanup;
}
//# sourceMappingURL=dashboard.d.ts.map