# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Julia
    module Shared
      extend T::Sig

      PROJECT_NAMES = T.let(%w[JuliaProject.toml Project.toml].freeze, T::Array[String])

      sig { params(version_str: String).returns(T::Array[String]) }
      def self.manifest_names(version_str)
        major, minor = version_str.split(".")
        # Prioritize versioned manifests over unversioned ones
        [
          "JuliaManifest-v#{major}.#{minor}.toml",
          "Manifest-v#{major}.#{minor}.toml",
          "JuliaManifest.toml",
          "Manifest.toml"
        ].freeze
      end

      # Match Julia project files case-insensitively
      # Note: This regex is used by FileFetcher for both file discovery and validation
      PROJECT_REGEX = T.let(/
        ^
        (?:Julia)?     # Optional "Julia" prefix
        Project\.toml  # Required suffix
        $
      /ix.freeze, Regexp)

      # Match Julia manifest files case-insensitively, including versioned ones
      MANIFEST_REGEX = T.let(/
        ^
        (?:Julia)?                # Optional "Julia" prefix
        Manifest                  # Base name
        (?:-v\d+\.\d+)?          # Optional version suffix like "-v1.2"
        \.toml                    # Required extension
        $
      /ix.freeze, Regexp)

      sig { params(filename: String).returns(T::Boolean) }
      def self.project_file?(filename)
        file_match?(filename, PROJECT_REGEX)
      end

      sig { params(filename: String).returns(T::Boolean) }
      def self.manifest_file?(filename)
        file_match?(filename, MANIFEST_REGEX)
      end

      sig { params(filename: String, pattern: Regexp).returns(T::Boolean) }
      def self.file_match?(filename, pattern)
        # Normalize path by removing leading slashes
        normalized_name = filename.sub(%r{^/*}, "")
        pattern.match?(normalized_name)
      end

      sig { params(manifest_name: String).returns(T.nilable([String, String])) }
      def self.version_from_manifest_name(manifest_name)
        if (match = manifest_name.match(/(?:Julia)?Manifest-v(\d+)\.(\d+)\.toml$/i))
          [match[1], match[2]]
        end
      end

      sig { params(project_path: String, manifest_path: String).returns(T::Boolean) }
      def self.valid_project_manifest_pair?(project_path, manifest_path)
        return false unless project_file?(project_path) && manifest_file?(manifest_path)

        # Must be in the same directory to be a valid pair
        File.dirname(project_path) == File.dirname(manifest_path)
      end
    end
  end
end
