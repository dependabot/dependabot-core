export interface LockDependency {
    dependencies?: Record<string, LockDependency>;
    [key: string]: unknown;
}
export declare function removeDependenciesFromLockfile(lockfile: LockDependency, dependencyNames: string[]): LockDependency;
