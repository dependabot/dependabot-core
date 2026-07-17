export type Requirement = Record<string, any>;
export interface Dependency {
    name: string;
    version?: string;
    requirements: Requirement[];
    previous_version?: string;
    previous_requirements?: Requirement[];
    directory?: string;
    package_manager: string;
    subdependency_metadata?: Record<string, string>[];
    removed?: boolean;
}
