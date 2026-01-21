import { Plugin } from '@opencode-ai/plugin';
interface RalphConfig {
    maxIterations: number;
    completionPromise: string;
    autoCommit: boolean;
    staleTimeout: number;
}
declare const defaultConfig: RalphConfig;
declare const slashCommands: ({
    command: string;
    description: string;
    arguments: string;
    options: {
        name: string;
        description: string;
    }[];
    examples: string[];
    alias?: undefined;
} | {
    command: string;
    alias: string[];
    description: string;
    arguments?: undefined;
    options?: undefined;
    examples?: undefined;
} | {
    command: string;
    alias: string[];
    arguments: string;
    description: string;
    examples: string[];
    options?: undefined;
})[];
declare const ralphSlash: Plugin;
export default ralphSlash;
export { slashCommands, RalphConfig, defaultConfig };
//# sourceMappingURL=index.d.ts.map