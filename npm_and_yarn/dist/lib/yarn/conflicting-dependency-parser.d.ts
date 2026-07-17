interface ConflictingDependency {
    explanation: string;
    name: string;
    version: string;
    requirement: string;
}
export declare function findConflictingDependencies(directory: string, depName: string, targetVersion: string): Promise<ConflictingDependency[]>;
export {};
