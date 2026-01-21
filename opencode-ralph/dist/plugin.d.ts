#!/usr/bin/env node
import { Plugin } from '@opencode-ai/plugin';
interface RalphConfig {
    maxIterations: number;
    completionPromise: string;
    autoCommit: boolean;
    staleTimeout: number;
    progressFile: string;
    historyFile: string;
}
declare const defaultConfig: RalphConfig;
declare const ralph: Plugin;
export default ralph;
export { RalphConfig, defaultConfig };
//# sourceMappingURL=plugin.d.ts.map