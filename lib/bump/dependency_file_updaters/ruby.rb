# frozen_string_literal: true
require "gemnasium/parser"
require "bundler"
require "bump/shared_helpers"
require "bump/errors"
require "bump/dependency_file_updaters/base"
require "bump/dependency_file_fetchers/ruby"

module Bump
  module DependencyFileUpdaters
    class Ruby < Base
      LOCKFILE_ENDING = /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m
      GIT_COMMAND_ERROR_REGEX = /`(?<command>.*)`/

      def updated_dependency_files
        [
          updated_file(file: gemfile, content: updated_gemfile_content),
          updated_file(file: lockfile, content: updated_lockfile_content)
        ]
      end

      private

      def required_files
        Bump::DependencyFileFetchers::Ruby.required_files
      end

      def gemfile
        @gemfile ||= get_original_file("Gemfile")
      end

      def lockfile
        @lockfile ||= get_original_file("Gemfile.lock")
      end

      def updated_gemfile_content
        return @updated_gemfile_content if @updated_gemfile_content

        gemfile.content.
          to_enum(:scan, Gemnasium::Parser::Patterns::GEM_CALL).
          find { Regexp.last_match[:name] == dependency.name }

        original_gem_declaration_string = Regexp.last_match.to_s
        updated_gem_declaration_string =
          original_gem_declaration_string.
          sub(Gemnasium::Parser::Patterns::REQUIREMENTS) do |old_requirements|
            old_version =
              old_requirements.match(Gemnasium::Parser::Patterns::VERSION)[0]

            precision = old_version.split(".").count
            new_version =
              dependency.version.split(".").first(precision).join(".")

            old_requirements.sub(old_version, new_version)
          end

        @updated_gemfile_content = gemfile.content.gsub(
          original_gem_declaration_string,
          updated_gem_declaration_string
        )
      end

      def updated_lockfile_content
        @updated_lockfile_content ||= build_updated_lockfile
      end

      def build_updated_lockfile
        lockfile_body =
          SharedHelpers.in_a_temporary_directory do |dir|
            write_temporary_dependency_files_to(dir)

            SharedHelpers.in_a_forked_process do
              definition = Bundler::Definition.build(
                File.join(dir, "Gemfile"),
                File.join(dir, "Gemfile.lock"),
                gems: [dependency.name]
              )
              definition.resolve_remotely!
              definition.to_lock
            end
          end
        post_process_lockfile(lockfile_body)
      rescue SharedHelpers::ChildProcessFailed => error
        handle_bundler_errors(error)
      end

      def handle_bundler_errors(error)
        case error.error_class
        when "Bundler::VersionConflict"
          raise Bump::VersionConflict
        when "Bundler::Source::Git::GitCommandError"
          command = error.message.match(GIT_COMMAND_ERROR_REGEX)[:command]
          raise Bump::GitCommandError, command
        else
          raise
        end
      end

      def write_temporary_dependency_files_to(dir)
        File.write(
          File.join(dir, "Gemfile"),
          prepare_gemfile_for_resolution(updated_gemfile_content)
        )
        File.write(
          File.join(dir, "Gemfile.lock"),
          lockfile.content.gsub(
            "git@github.com:",
            "https://#{github_access_token}:x-oauth-basic@github.com/"
          )
        )
      end

      def prepare_gemfile_for_resolution(gemfile_content)
        # Prepend auth details to any git remotes
        gemfile_content =
          gemfile_content.gsub(
            "git@github.com:",
            "https://#{github_access_token}:x-oauth-basic@github.com/"
          )

        # Remove any explicit Ruby version, as a mismatch with the system Ruby
        # version during dependency resolution will cause an error.
        #
        # Ideally we would run this class using whichever Ruby version was
        # specified, but that's impractical, and it's better to produce a PR
        # for the user with gems that require a bump to their Ruby version than
        # not to produce a PR at all.
        gemfile_content.gsub(/^ruby\b/, "# ruby")
      end

      def post_process_lockfile(lockfile_body)
        # Remove any auth details we prepended to git remotes
        lockfile_body =
          lockfile_body.gsub(
            "https://#{github_access_token}:x-oauth-basic@github.com/",
            "git@github.com:"
          )

        # Re-add any explicit Ruby version, and the old `BUNDLED WITH` version
        lockfile_body.gsub(
          LOCKFILE_ENDING,
          lockfile.content.match(LOCKFILE_ENDING)&.[](:ending) || "\n"
        )
      end
    end
  end
end
