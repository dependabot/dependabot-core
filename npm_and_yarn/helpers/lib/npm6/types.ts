// Mirrors Dependabot::Dependency#requirements entries from Ruby,
// which are T::Hash[Symbol, T.untyped] — an unstructured hash.
export type Requirement = Record<string, any>;

// Represents a serialized Dependabot::Dependency from the Ruby codebase (via Dependency#to_h).
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

