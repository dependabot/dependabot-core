interface PnpmDependency {
    name: string;
    version: string;
    resolved: string | undefined;
    dev: boolean;
    specifiers: string[];
    aliased: boolean;
}
export declare function parse(directory: string): Promise<PnpmDependency[]>;
export {};
