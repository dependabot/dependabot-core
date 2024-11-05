# typed: strong
# frozen_string_literal: true

module Dependabot
  module Bundler
    module Helpers
      extend T::Sig
      extend T::Helpers

      V1 = "1"
      V2 = "2"
      # If we are updating a project with no Gemfile.lock, we default to the
      # newest version we support
      DEFAULT = V2
      BUNDLER_MAJOR_VERSION_REGEX = /BUNDLED WITH\s+(?<version>\d+)\./m

      GEMFILE = "Gemfile"
      GEMSPEC_EXTENSION = ".gemspec"
      BUNDLER_GEM_NAME = "bundler"
      BUNDLER_REQUIREMENT_REGEX = /gem\s+['"]#{BUNDLER_GEM_NAME}['"],\s*['"](.+?)['"]/

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

      sig { params(files: T::Array[Dependabot::DependencyFile]).returns(T.nilable(String)) }
      def self.bundler_requirement(files)
        # Search through provided files for an explicit Bundler requirement
        files.each do |file|
          # Only check relevant files (Gemfile or .gemspec files)
          next unless file.name.end_with?(GEMFILE, GEMSPEC_EXTENSION)

          # Check for a Bundler version requirement in the file content
          if T.let(file.content, T.nilable(String))&.match(BUNDLER_REQUIREMENT_REGEX)
            return Regexp.last_match(1) # Return the matched requirement (e.g., "~> 2.0")
          end
        end
        nil
      end
    end
  end
end
