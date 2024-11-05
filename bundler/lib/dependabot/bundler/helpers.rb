# typed: strict
# frozen_string_literal: true

module Dependabot
  module Bundler
    module Helpers
      extend T::Sig
      extend T::Helpers

      V1 = "1"
      V2 = "2"
      DEFAULT = V2
      BUNDLER_MAJOR_VERSION_REGEX = /BUNDLED WITH\s+(?<version>\d+)\./m

      GEMFILE = "Gemfile"
      GEMSPEC_EXTENSION = ".gemspec"
      BUNDLER_GEM_NAME = "bundler"
      BUNDLER_REQUIREMENT_REGEX = /gem\s+['"]#{BUNDLER_GEM_NAME}['"],\s*((['"].+?['"],\s*)*['"].+?['"])/

      sig { params(lockfile: T.nilable(Dependabot::DependencyFile)).returns(String) }
      def self.bundler_version(lockfile)
        return DEFAULT unless lockfile

        if (matches = T.let(lockfile.content, T.nilable(String))&.match(BUNDLER_MAJOR_VERSION_REGEX))
          matches[:version].to_i >= 2 ? V2 : V1
        else
          DEFAULT
        end
      end

      sig { params(lockfile: T.nilable(Dependabot::DependencyFile)).returns(String) }
      def self.detected_bundler_version(lockfile)
        return "unknown" unless lockfile

        if (matches = T.let(lockfile.content, T.nilable(String))&.match(BUNDLER_MAJOR_VERSION_REGEX))
          matches[:version].to_i.to_s
        else
          "unspecified"
        end
      end

      # Combines all version constraints for `bundler` in the given files into a single requirement
      sig { params(files: T::Array[Dependabot::DependencyFile]).returns(T.nilable(Requirement)) }
      def self.bundler_version_requirement(files)
        bundler_version_constraints = bundler_version_constraints(files)

        return nil if bundler_version_constraints.none?

        combined_constraint = bundler_version_constraints.join(", ")

        Requirement.new(combined_constraint)
      end

      # Extracts all version constraints for `bundler` from the given files
      sig { params(files: T::Array[Dependabot::DependencyFile]).returns(T::Array[String]) }
      def self.bundler_version_constraints(files)
        files.each do |file|
          next unless file.name.end_with?(GEMFILE, GEMSPEC_EXTENSION)

          next unless (match = T.let(file.content, T.nilable(String))&.match(BUNDLER_REQUIREMENT_REGEX))

          constraints_string = match[1]

          return [] unless constraints_string

          scanned_constraints = constraints_string.scan(/['"][^'"]+['"]/)
          constraints = T.let(scanned_constraints.flatten, T::Array[String])

          return constraints.map { |req| req.tr('"\'', "") }
        end
        []
      end
    end
  end
end
