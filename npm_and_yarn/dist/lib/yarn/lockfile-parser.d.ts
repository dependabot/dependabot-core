export interface LockfileEntry {
    version: string;
    resolved?: string;
    dependencies?: Record<string, string>;
}
export declare function parse(directory: string): Promise<Record<string, LockfileEntry>>;
