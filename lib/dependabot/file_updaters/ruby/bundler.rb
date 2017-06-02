# frozen_string_literal: true
require "gemnasium/parser"
require "bundler"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/file_updaters/base"
require "dependabot/file_fetchers/ruby/bundler"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler < Dependabot::FileUpdaters::Base
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
          Dependabot::FileFetchers::Ruby::Bundler.required_files
        end

        def gemfile
          @gemfile ||= get_original_file("Gemfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Gemfile.lock")
        end

        def updated_gemfile_content
          @updated_gemfile_content ||=
            gemfile.content.gsub(
              original_gem_declaration_string,
              updated_gem_declaration_string
            )
        end

        def original_gem_declaration_string
          @original_gem_declaration_string ||=
            begin
              regex = Gemnasium::Parser::Patterns::GEM_CALL
              matches = []

              gemfile.content.scan(regex) { matches << Regexp.last_match }
              matches.find { |match| match[:name] == dependency.name }.to_s
            end
        end

        def updated_gem_declaration_string
          original_gem_declaration_string.
            sub(Gemnasium::Parser::Patterns::REQUIREMENTS) do |old_req|
              old_req.sub(Gemnasium::Parser::Patterns::VERSION) do |old_version|
                precision = old_version.split(".").count
                dependency.version.split(".").first(precision).join(".")
              end
            end
        end

        def updated_lockfile_content
          @updated_lockfile_content ||= build_updated_lockfile
        end

        def build_updated_lockfile
          lockfile_body =
            SharedHelpers.in_a_temporary_directory do |dir|
              write_temporary_dependency_files_to(dir)

              SharedHelpers.in_a_forked_process do
                definition = ::Bundler::Definition.build(
                  File.join(dir, "Gemfile"),
                  File.join(dir, "Gemfile.lock"),
                  gems: [dependency.name]
                )
                definition.resolve_remotely!
                definition.to_lock
              end
            end
          post_process_lockfile(lockfile_body)
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
          # for the user with gems that require a bump to their Ruby version
          # than not to produce a PR at all.
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
end
