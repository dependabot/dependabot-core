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
        ).returns(Gem::Version)
      end
      def self.ruby_version(gemfile, lockfile)
        ruby_version = ruby_version_from_ruby_version_file

        ruby_version = ruby_version_from_lockfile(lockfile) if ruby_version.nil?

        ruby_version = ruby_version_from_definition(gemfile, lockfile) if ruby_version.nil?

        ruby_version = RUBY_VERSION if ruby_version.nil?

        Gem::Version.new(ruby_version)
      end

      sig do
        params(
          lockfile: T.nilable(Dependabot::DependencyFile)
        ).returns(T.nilable(String))
      end
      def self.ruby_version_from_lockfile(lockfile)
        return nil unless lockfile

        ruby_version = lockfile.content&.match(/RUBY VERSION\s+(?<version>[^\s]+)/)&.named_captures&.fetch(
          "version", nil
        )
        ruby_version
      end

      sig do
        params(
          gemfile: T.nilable(Dependabot::DependencyFile),
          lockfile: T.nilable(Dependabot::DependencyFile)
        )
          .returns(T.nilable(String))
      end
      def self.ruby_version_from_definition(gemfile, lockfile)
        gemfile_name = gemfile&.name
        return nil unless gemfile_name

        ruby_version = T.let(build_definition(gemfile, lockfile).ruby_version, ::Bundler::RubyVersion)

        gem_version = T.let(ruby_version.gem_version, T.nilable(Gem::Version))

        return nil unless gem_version

        gem_version.to_s
      end

      sig do
        params(
          gemfile: T.nilable(Dependabot::DependencyFile),
          lockfile: T.nilable(Dependabot::DependencyFile)
        ).returns(::Bundler::Definition)
      end
      def self.build_definition(gemfile, lockfile)
        gemfile_name = gemfile&.name
        lockfile_name = lockfile&.name
        T.let(
          ::Bundler::Definition.build(
            gemfile_name,
            lockfile_name,
            gems: []
          ), ::Bundler::Definition
        )
      end

      sig { returns(T.nilable(String)) }
      def self.ruby_version_from_ruby_version_file
        # Ensure file_content is either a String or nil
        file_content = T.let(::Bundler.read_file(".ruby-version"), T.nilable(String))

        return nil unless file_content.is_a?(String)

        # Regex match to extract the Ruby version
        ruby_version = if /^ruby(-|\s+)?([^\s#]+)/ =~ file_content
                         T.let(::Regexp.last_match(2), T.nilable(String))
                       else
                         T.let(file_content.strip, T.nilable(String))
                       end

        ruby_version
      rescue SystemCallError
        # Handle .ruby-version file not existing, return nil
        nil
      end
    end
  end
end
