interface Dependency {
    name: string;
    [key: string]: any;
}
export declare function updateDependencyFile(directory: string, lockfileName: string, dependencies: Dependency[]): Promise<Record<string, string>>;
export {};
