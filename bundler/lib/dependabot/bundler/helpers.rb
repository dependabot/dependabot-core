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
      RUBY_VERSION_REGEX = /RUBY VERSION\s+ruby\s+([^\s]+)/

      sig { params(lockfile: T.nilable(Dependabot::DependencyFile)).returns(String) }
      def self.bundler_version(lockfile)
        return DEFAULT unless lockfile

        if (matches = lockfile.content&.match(BUNDLER_MAJOR_VERSION_REGEX))
          matches[:version].to_i >= 2 ? V2 : V1
        else
          DEFAULT
        end
      end

      sig { params(lockfile: T.nilable(Dependabot::DependencyFile)).returns(String) }
      def self.detected_bundler_version(lockfile)
        return "unknown" unless lockfile

        if (matches = lockfile.content&.match(BUNDLER_MAJOR_VERSION_REGEX))
          matches[:version].to_i.to_s
        else
          "unspecified"
        end
      end

      sig do
        params(
          gemfile: T.nilable(Dependabot::DependencyFile),
          lockfile: T.nilable(Dependabot::DependencyFile)
        ).returns(String)
      end
      def self.ruby_version(gemfile, lockfile)
        ruby_version = ruby_version_from_ruby_version_file

        ruby_version = ruby_version_from_lockfile(lockfile) if ruby_version.nil?
        ruby_version = ruby_version_from_gemfile(gemfile) if ruby_version.nil?

        # If we still don't have a Ruby version, the version Dependabot is running on is used
        ruby_version || RUBY_VERSION
      end

      sig do
        params(
          lockfile: T.nilable(Dependabot::DependencyFile)
        ).returns(T.nilable(String))
      end
      def self.ruby_version_from_lockfile(lockfile)
        return nil unless lockfile

        # Use the updated regex to capture the Ruby version
        lockfile.content&.match(RUBY_VERSION_REGEX)&.captures&.first
      end

      sig do
        params(
          gemfile: T.nilable(Dependabot::DependencyFile)
        ).returns(T.nilable(String))
      end
      def self.ruby_version_from_gemfile(gemfile)
        gemfile_content = gemfile&.content
        return nil unless gemfile_content

        # Capture the version as a String explicitly
        ruby_version = gemfile_content[/ruby\s+['"]([\d.]+)['"]/, 1]
        T.let(ruby_version, T.nilable(String))
      end

      sig { returns(T.nilable(String)) }
      def self.ruby_version_from_ruby_version_file
        begin
          file_content = File.read(".ruby-version").strip
        rescue SystemCallError
          # Handle .ruby-version file not existing, return nil
          return nil
        end

        # Regex to extract the Ruby version
        file_content[/^ruby(-|\s+)?([^\s#]+)/, 2] || file_content
      end
    end
  end
end
