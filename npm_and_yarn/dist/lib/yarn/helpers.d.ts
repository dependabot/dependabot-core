export declare function isString(value: unknown): value is string;
export type Requirement = Record<string, any>;
declare const LightweightAdd_base: any;
declare class LightweightAdd extends LightweightAdd_base {
    constructor(...args: any[]);
    bailout(patterns: any, workspaceLayout: any): Promise<boolean>;
}
declare const LightweightInstall_base: any;
declare class LightweightInstall extends LightweightInstall_base {
    constructor(...args: any[]);
    bailout(patterns: any, workspaceLayout: any): Promise<boolean>;
}
export declare const LOCKFILE_ENTRY_REGEX: RegExp;
export { LightweightAdd, LightweightInstall };
