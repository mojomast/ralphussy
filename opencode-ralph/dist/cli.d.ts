#!/usr/bin/env node
interface RalphOptions {
    prompt: string;
    maxIterations: number;
    completionPromise: string;
    model: string | null;
    verbose: boolean;
    attach: string | null;
}
export declare class RalphCLI {
    private stateDir;
    private progressFile;
    private historyFile;
    private client;
    private server;
    constructor();
    run(options: RalphOptions): Promise<void>;
    private runIteration;
    private runWithClient;
    private runOpenCode;
    private extractTools;
    private detectStruggle;
    private ensureStateDir;
    private initState;
    private logProgress;
    private appendHistory;
    private printSummary;
    status(): Promise<void>;
    addContext(context: string): Promise<void>;
    clearContext(): Promise<void>;
}
export {};
//# sourceMappingURL=cli.d.ts.map