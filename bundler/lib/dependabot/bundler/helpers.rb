# typed: strong
# frozen_string_literal: true

require "dependabot/bundler/requirement"

module Dependabot
  module Bundler
    module Helpers
      extend T::Sig
      extend T::Helpers

      V1 = "1"
      V2 = "2"
      DEFAULT = V2
      BUNDLER_MAJOR_VERSION_REGEX = /BUNDLED WITH\s+(?<version>\d+)\./m
      RUBY_GEMFILE_REGEX = /^ruby\s+['"]([^'"]+)['"]/
      RUBY_GEMSPEC_REGEX = /required_ruby_version\s+=\s+['"]([^'"]+)['"]/

      GEMFILE = "Gemfile"
      GEMSPEC_EXTENSION = ".gemspec"
      BUNDLER_GEM_NAME = "bundler"
      LANGUAGE = "ruby"

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

      # Method to get the Requirement object for the 'bundler' dependency
      sig do
        params(
          dependency_name: String,
          files: T::Array[Dependabot::DependencyFile]
        ).returns(T.nilable(Dependabot::Bundler::Requirement))
      end
      def self.dependency_requirement(dependency_name, files)
        constraints = combined_dependency_constraints(files, dependency_name)
        return nil if constraints.empty?

        combined_constraint = constraints.join(", ")

        Dependabot::Bundler::Requirement.new(combined_constraint)
      rescue StandardError => e
        Dependabot.logger.error(
          "Failed to create Requirement with constraints '#{constraints&.join(', ')}': #{e.message}"
        )
        nil
      end

      # Method to gather and combine constraints for a specified dependency from multiple files
      sig do
        params(files: T::Array[Dependabot::DependencyFile], dependency_name: String).returns(T::Array[String])
      end
      def self.combined_dependency_constraints(files, dependency_name)
        files.each_with_object([]) do |file, result|
          content = file.content
          next unless content

          # Select the appropriate regex based on file type and dependency name
          regex = if dependency_name == LANGUAGE
                    ruby_version_regex(file.name)
                  elsif file.name.end_with?(GEMFILE)
                    gemfile_dependency_regex(dependency_name)
                  elsif file.name.end_with?(GEMSPEC_EXTENSION)
                    gemspec_dependency_regex(dependency_name)
                  else
                    next # Skip unsupported file types, including .ruby-version
                  end

          # If regex is nil (unsupported for this file type), skip to the next file
          next unless regex

          # Extract constraints using the chosen regex
          result.concat(extract_constraints_from_file(content, regex))
        end.uniq
      end

      # Method to generate the regex pattern for Ruby version in Gemfile or gemspec
      sig { params(file_name: String).returns(T.nilable(Regexp)) }
      def self.ruby_version_regex(file_name)
        if file_name.end_with?(GEMFILE)
          RUBY_GEMFILE_REGEX
        elsif file_name.end_with?(GEMSPEC_EXTENSION)
          RUBY_GEMSPEC_REGEX
        end
      end

      # Method to generate the regex pattern for a dependency in a Gemfile
      sig { params(dependency_name: String).returns(Regexp) }
      def self.gemfile_dependency_regex(dependency_name)
        /gem\s+['"]#{Regexp.escape(dependency_name)}['"](?:,\s*['"]([^'"]+)['"])?/
      end

      # Method to generate the regex pattern for a dependency in a gemspec file
      sig { params(dependency_name: String).returns(Regexp) }
      def self.gemspec_dependency_regex(dependency_name)
        /add_(?:runtime_)?dependency\s+['"]#{Regexp.escape(dependency_name)}['"],\s*['"]([^'"]+)['"]/
      end

      # Extracts constraints from file content based on a dependency regex
      sig { params(content: String, regex: Regexp).returns(T::Array[String]) }
      def self.extract_constraints_from_file(content, regex)
        if content.match(regex)
          content.scan(regex).flatten
        else
          []
        end
      end
    end
  end
end
