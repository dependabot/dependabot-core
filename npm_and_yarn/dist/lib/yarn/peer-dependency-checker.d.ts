import { type Requirement } from "./helpers.js";
export declare function checkPeerDependencies(directory: string, depName: string, desiredVersion: string, requirements: Requirement[]): Promise<void>;
