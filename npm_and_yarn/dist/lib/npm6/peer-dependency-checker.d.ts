import type { Dependency, Requirement } from "./types.js";
export declare function checkPeerDependencies(directory: string, depName: string, desiredVersion: string, requirements: Requirement[], topLevelDependencies?: Dependency[]): Promise<void>;
