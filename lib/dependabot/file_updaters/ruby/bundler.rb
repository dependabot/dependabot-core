# frozen_string_literal: true
require "gemnasium/parser"
require "bundler"
require "bundler_definition_version_patch"
require "bundler_metadata_dependencies_patch"
require "bundler_git_source_patch"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler < Dependabot::FileUpdaters::Base
        LOCKFILE_ENDING = /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m
        DEPENDENCY_DECLARATION_REGEX =
          /^\s*\w*\.add(?:_development|_runtime)?_dependency
            (\s*|\()['"](?<name>.*?)['"],
            \s*(?<requirements>.*)\)?/x

        def self.updated_files_regex
          [
            /^Gemfile$/,
            /^Gemfile\.lock$/,
            %r{^[^/]*\.gemspec$}
          ]
        end

        def updated_dependency_files
          updated_files = []

          if gemfile && gemfile_changed?
            updated_files <<
              updated_file(file: gemfile, content: updated_gemfile_content)
          end

          if lockfile
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          if gemspec && gemspec_changed?
            updated_files <<
              updated_file(file: gemspec, content: updated_gemspec_content)
          end

          updated_files
        end

        private

        def check_required_files
          file_names = dependency_files.map(&:name)

          if file_names.include?("Gemfile.lock") &&
             !file_names.include?("Gemfile")
            raise "A Gemfile must be provided if a lockfile is!"
          end

          return if file_names.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
          return if (%w(Gemfile Gemfile.lock) - file_names).empty?

          raise "A gemspec or a Gemfile and Gemfile.lock must be provided!"
        end

        def gemfile
          @gemfile ||= get_original_file("Gemfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Gemfile.lock")
        end

        def gemfile_changed?
          original_gemfile_declaration_string &&
            original_gemfile_declaration_string !=
              updated_gemfile_declaration_string
        end

        def gemspec_changed?
          original_gemspec_declaration_string &&
            original_gemspec_declaration_string !=
              updated_gemspec_declaration_string
        end

        def updated_gemfile_content
          return gemfile.content unless original_gemfile_declaration_string
          @updated_gemfile_content ||= gemfile.content.gsub(
            original_gemfile_declaration_string,
            updated_gemfile_declaration_string
          )
        end

        def updated_gemspec_content
          return gemspec.content unless original_gemspec_declaration_string
          @updated_gemspec_content ||= gemspec.content.gsub(
            original_gemspec_declaration_string,
            updated_gemspec_declaration_string
          )
        end

        def original_gemfile_declaration_string
          @original_gemfile_declaration_string ||=
            begin
              regex = Gemnasium::Parser::Patterns::GEM_CALL
              matches = []

              gemfile.content.scan(regex) { matches << Regexp.last_match }
              matches.find { |match| match[:name] == dependency.name }&.to_s
            end
        end

        def updated_gemfile_declaration_string
          original_gemfile_declaration_string.
            sub(Gemnasium::Parser::Patterns::REQUIREMENTS) do |old_req|
              new_req = old_req.dup.gsub(/<=?/, "~>")
              new_req.sub(Gemnasium::Parser::Patterns::VERSION) do |old_version|
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
            updated_gemfile_content
          )
          File.write(
            "Gemfile.lock",
            lockfile.content
          )

          if gemspec
            File.write(
              gemspec.name,
              sanitized_gemspec_content(updated_gemspec)
            )
          end

          write_ruby_version_file

          path_gemspecs.compact.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitized_gemspec_content(file))
          end
        end

        def write_ruby_version_file
          return unless ruby_version_file
          path = ruby_version_file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, ruby_version_file.content)
        end

        def path_gemspecs
          all = dependency_files.select { |f| f.name.end_with?(".gemspec") }
          all - [gemspec]
        end

        def gemspec
          dependency_files.find { |f| f.name.match?(%r{^[^/]*\.gemspec$}) }
        end

        def updated_gemspec
          updated_file(file: gemspec, content: updated_gemspec_content)
        end

        def ruby_version_file
          dependency_files.find { |f| f.name == ".ruby-version" }
        end

        def post_process_lockfile(lockfile_body)
          # Re-add the old `BUNDLED WITH` version (and remove the RUBY VERSION
          # if it wasn't previously present in the lockfile)
          lockfile_body.gsub(
            LOCKFILE_ENDING,
            lockfile.content.match(LOCKFILE_ENDING)&.[](:ending) || "\n"
          )
        end

        def sanitized_gemspec_content(gemspec)
          gemspec_content = gemspec.content.gsub(/^\s*require.*$/, "")
          gemspec_content.gsub(/=.*VERSION.*$/) do
            parsed_lockfile ||= ::Bundler::LockfileParser.new(lockfile.content)
            gem_name = gemspec.name.split("/").last.split(".").first
            spec = parsed_lockfile.specs.find { |s| s.name == gem_name }
            "='#{spec.version}'"
          end
        end

        def original_gemspec_declaration_string
          @original_gemspec_declaration_string ||=
            begin
              matches = []
              gemspec.content.scan(DEPENDENCY_DECLARATION_REGEX) do
                matches << Regexp.last_match
              end
              matches.find { |match| match[:name] == dependency.name }&.to_s
            end
        end

        def updated_gemspec_declaration_string
          original_requirement = DEPENDENCY_DECLARATION_REGEX.match(
            original_gemspec_declaration_string
          )[:requirements]

          quote_character = original_requirement.include?("'") ? "'" : '"'

          formatted_new_requirement =
            dependency.requirement.split(",").
            map { |r| %(#{quote_character}#{r.strip}#{quote_character}) }.
            join(", ")

          original_gemspec_declaration_string.
            sub(original_requirement, formatted_new_requirement)
        end
      end
    end
  end
end
