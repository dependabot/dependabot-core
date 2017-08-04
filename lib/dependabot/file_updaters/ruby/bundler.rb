# frozen_string_literal: true
require "gemnasium/parser"
require "bundler"
require "bundler_definition_version_patch"
require "bundler_metadata_dependencies_patch"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/file_updaters/base"
require "dependabot/file_fetchers/ruby/bundler"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler < Dependabot::FileUpdaters::Base
        LOCKFILE_ENDING = /(?<ending>\s*BUNDLED WITH.*)/m

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
              new_req = old_req.dup.gsub(/<=?/, "~>")
              new_req.sub(Gemnasium::Parser::Patterns::VERSION) do |old_version|
                precision = old_version.split(".").count
                dependency.version.segments.first(precision).join(".")
              end
            end
        end

        def updated_lockfile_content
          @updated_lockfile_content ||= build_updated_lockfile
        end

        def build_updated_lockfile
          lockfile_body =
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))
                ::Bundler.settings["github.com"] =
                  "x-access-token:#{github_access_token}"

                definition = ::Bundler::Definition.build(
                  "Gemfile",
                  "Gemfile.lock",
                  gems: [dependency.name]
                )
                definition.resolve_remotely!
                definition.to_lock
              end
            end
          post_process_lockfile(lockfile_body)
        end

        def write_temporary_dependency_files
          File.write(
            "Gemfile",
            replace_ssh_links_with_https(updated_gemfile_content)
          )
          File.write(
            "Gemfile.lock",
            replace_ssh_links_with_https(lockfile.content)
          )
          [*gemspecs, ruby_version_file].compact.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
        end

        def gemspecs
          dependency_files.select { |f| f.name.end_with?(".gemspec") }
        end

        def ruby_version_file
          dependency_files.find { |f| f.name == ".ruby-version" }
        end

        def replace_ssh_links_with_https(content)
          # NOTE: we use the full x-access-token format so that we can identify
          # the links we changed when post-processing the lockfile
          content.gsub(
            "git@github.com:",
            "https://x-access-token:#{github_access_token}@github.com/"
          )
        end

        def post_process_lockfile(lockfile_body)
          # Remove any auth details we prepended to git remotes
          lockfile_body =
            lockfile_body.gsub(
              "https://x-access-token:#{github_access_token}@github.com/",
              "git@github.com:"
            )

          # Re-add the old `BUNDLED WITH` version
          lockfile_body.gsub(
            LOCKFILE_ENDING,
            lockfile.content.match(LOCKFILE_ENDING)&.[](:ending) || "\n"
          )
        end
      end
    end
  end
end
