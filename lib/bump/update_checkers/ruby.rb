# frozen_string_literal: true
require "gems"
require "gemnasium/parser"
require "bump/update_checkers/base"
require "bump/shared_helpers"
require "bump/errors"

module Bump
  module UpdateCheckers
    class Ruby < Base
      GIT_COMMAND_ERROR_REGEX = /`(?<command>.*)`/

      def latest_version
        @latest_version ||= updated_gem_version
      end

      private

      def updated_gem_version
        @updated_gem_version ||=
          SharedHelpers.in_a_temporary_directory do |dir|
            write_temporary_dependency_files_to(dir)

            SharedHelpers.in_a_forked_process do
              definition = Bundler::Definition.build(
                File.join(dir, "Gemfile"),
                File.join(dir, "Gemfile.lock"),
                gems: [dependency.name]
              )

              dependency_source = get_dependency_source(definition, dependency)

              # We don't want to bump gems with a git source, so exit early
              next nil if dependency_source.is_a?(Bundler::Source::Git)

              get_latest_resolvable_version(definition, dependency)
            end
          end
      rescue SharedHelpers::ChildProcessFailed => error
        handle_bundler_errors(error)
      end

      def handle_bundler_errors(error)
        case error.error_class
        when "Bundler::VersionConflict"
          raise Bump::VersionConflict
        when "Bundler::Dsl::DSLError"
          msg = error.error_class + " with message: " + error.error_message
          raise Bump::DependencyFileNotEvaluatable, msg
        when "Bundler::Source::Git::GitCommandError"
          command = error.message.match(GIT_COMMAND_ERROR_REGEX)[:command]
          raise Bump::GitCommandError, command
        when "Bundler::PathError"
          raise if path_based_dependencies.none?
          raise Bump::PathBasedDependencies, path_based_dependencies
        else
          raise
        end
      end

      def gemfile
        gemfile = dependency_files.find { |f| f.name == "Gemfile" }
        raise "No Gemfile!" unless gemfile
        gemfile
      end

      def lockfile
        lockfile = dependency_files.find { |f| f.name == "Gemfile.lock" }
        raise "No Gemfile.lock!" unless lockfile
        lockfile
      end

      def get_dependency_source(definition, dependency)
        definition.dependencies.find { |d| d.name == dependency.name }.source
      end

      def get_latest_resolvable_version(definition, dependency)
        definition.resolve_remotely!
        definition.resolve.find { |dep| dep.name == dependency.name }.version
      end

      def path_based_dependencies
        Bundler::LockfileParser.new(lockfile.content).specs.select do |spec|
          spec.source.is_a?(Bundler::Source::Path)
        end
      end

      def write_temporary_dependency_files_to(dir)
        File.write(
          File.join(dir, "Gemfile"),
          gemfile_for_update_check
        )
        File.write(
          File.join(dir, "Gemfile.lock"),
          lockfile_for_update_check
        )
      end

      def gemfile_for_update_check
        gemfile_content = gemfile.content
        gemfile_content = remove_dependency_requirement(gemfile_content)
        gemfile_content = prepend_git_auth_details(gemfile_content)
        remove_ruby_declaration(gemfile_content)
      end

      def lockfile_for_update_check
        lockfile_content = lockfile.content
        prepend_git_auth_details(lockfile_content)
      end

      # Replace the original gem requirements with nothing, to fully "unlock"
      # the gem during version checking
      def remove_dependency_requirement(gemfile_content)
        gemfile_content.
          to_enum(:scan, Gemnasium::Parser::Patterns::GEM_CALL).
          find { Regexp.last_match[:name] == dependency.name }

        original_gem_declaration_string = Regexp.last_match.to_s
        updated_gem_declaration_string =
          original_gem_declaration_string.
          sub(/,[ \t]*#{Gemnasium::Parser::Patterns::REQUIREMENTS}/, "")

        gemfile_content.gsub(
          original_gem_declaration_string,
          updated_gem_declaration_string
        )
      end

      def prepend_git_auth_details(gemfile_content)
        gemfile_content.gsub(
          "git@github.com:",
          "https://#{github_access_token}:x-oauth-basic@github.com/"
        )
      end

      def remove_ruby_declaration(gemfile_content)
        # Remove any explicit Ruby version, as a mismatch with the system Ruby
        # version during dependency resolution will cause an error.
        #
        # Ideally we would run this class using whichever Ruby version was
        # specified, but that's impractical, and it's better to produce a PR
        # for the user with gems that require a bump to their Ruby version than
        # not to produce a PR at all.
        gemfile_content.gsub(/^ruby\b/, "# ruby")
      end
    end
  end
end
