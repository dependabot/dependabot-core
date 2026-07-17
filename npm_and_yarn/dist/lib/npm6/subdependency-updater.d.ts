import type { Dependency } from "./types.js";
export declare function updateDependencyFile(directory: string, lockfileName: string, dependencies: Dependency[]): Promise<Record<string, string>>;
