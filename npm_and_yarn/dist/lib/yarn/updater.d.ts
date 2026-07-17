import { type Requirement } from "./helpers.js";
interface Dependency {
    name: string;
    version: string;
    requirements: Requirement[];
}
export declare function updateDependencyFiles(directory: string, dependencies: Dependency[]): Promise<Record<string, string>>;
export {};
