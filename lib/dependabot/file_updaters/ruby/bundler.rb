# frozen_string_literal: true

require "bundler"

require "bundler_definition_version_patch"
require "bundler_git_source_patch"

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/file_updaters/base"

require "rubygems_yaml_load_patch"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler < Dependabot::FileUpdaters::Base
        require "dependabot/file_updaters/ruby/bundler/git_pin_replacer"
        require "dependabot/file_updaters/ruby/bundler/git_source_remover"
        require "dependabot/file_updaters/ruby/bundler/requirement_replacer"

        LOCKFILE_ENDING = /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m
        DEPENDENCY_DECLARATION_REGEX =
          /^\s*\w*\.add(?:_development|_runtime)?_dependency
            (\s*|\()['"](?<name>.*?)['"],
            \s*(?<requirements>.*?)\)?\s*$/x

        def self.updated_files_regex
          [
            /^Gemfile$/,
            /^Gemfile\.lock$/,
            %r{^[^/]*\.gemspec$}
          ]
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def updated_dependency_files
          updated_files = []

          if gemfile && file_changed?(gemfile)
            updated_files <<
              updated_file(
                file: gemfile,
                content: updated_gemfile_content(gemfile)
              )
          end

          if lockfile && dependency.appears_in_lockfile?
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          if gemspec && file_changed?(gemspec)
            updated_files <<
              updated_file(file: gemspec, content: updated_gemspec_content)
          end

          evaled_gemfiles.each do |file|
            next unless file_changed?(file)
            updated_files <<
              updated_file(
                file: file,
                content: updated_gemfile_content(file)
              )
          end

          updated_files
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        private

        def check_required_files
          file_names = dependency_files.map(&:name)

          if file_names.include?("Gemfile.lock") &&
             !file_names.include?("Gemfile")
            raise "A Gemfile must be provided if a lockfile is!"
          end

          return if file_names.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
          return if file_names.include?("Gemfile")

          raise "A gemspec or Gemfile must be provided!"
        end

        def gemfile
          @gemfile ||= get_original_file("Gemfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Gemfile.lock")
        end

        def evaled_gemfiles
          @evaled_gemfiles ||=
            dependency_files.
            reject { |f| f.name.end_with?(".gemspec") }.
            reject { |f| f.name.end_with?(".lock") }.
            reject { |f| f.name.end_with?(".ruby-version") }.
            reject { |f| f.name == "Gemfile" }
        end

        def file_changed?(file)
          changed_requirements =
            dependency.requirements - dependency.previous_requirements

          changed_requirements.any? { |f| f[:file] == file.name }
        end

        def remove_git_source?
          old_gemfile_req =
            dependency.previous_requirements.find { |f| f[:file] == "Gemfile" }
          return false unless old_gemfile_req&.dig(:source, :type) == "git"

          new_gemfile_req =
            dependency.requirements.find { |f| f[:file] == "Gemfile" }

          new_gemfile_req[:source].nil?
        end

        def update_git_pin?
          new_gemfile_req =
            dependency.requirements.find { |f| f[:file] == "Gemfile" }
          return false unless new_gemfile_req&.dig(:source, :type) == "git"

          # If the new requirement is a git dependency with a ref then there's
          # no harm in doing an update
          new_gemfile_req.dig(:source, :ref)
        end

        def updated_gemfile_content(file)
          content = replace_gemfile_version_requirement(file.content)
          content = remove_gemfile_git_source(content) if remove_git_source?
          content = update_gemfile_git_pin(content) if update_git_pin?
          content
        end

        def updated_gemspec_content
          replace_gemspec_version_requirement(gemspec.content)
        end

        def replace_gemfile_version_requirement(content)
          return content unless file_changed?(gemfile)

          updated_requirement =
            dependency.requirements.
            find { |r| r[:file] == gemfile.name }.
            fetch(:requirement)

          RequirementReplacer.new(
            dependency: dependency,
            file_type: :gemfile,
            updated_requirement: updated_requirement
          ).rewrite(content)
        end

        def remove_gemfile_git_source(content)
          GitSourceRemover.new(dependency: dependency).rewrite(content)
        end

        def update_gemfile_git_pin(content)
          new_pin =
            dependency.requirements.
            find { |f| f[:file] == "Gemfile" }.
            fetch(:source).fetch(:ref)

          GitPinReplacer.
            new(dependency: dependency, new_pin: new_pin).
            rewrite(content)
        end

        def replace_gemspec_version_requirement(content)
          return content unless file_changed?(gemspec)

          updated_requirement =
            dependency.requirements.
            find { |r| r[:file] == gemspec.name }.
            fetch(:requirement)

          RequirementReplacer.new(
            dependency: dependency,
            file_type: :gemspec,
            updated_requirement: updated_requirement
          ).rewrite(content)
        end

        def updated_lockfile_content
          @updated_lockfile_content ||= build_updated_lockfile
        end

        def build_updated_lockfile
          lockfile_body =
            SharedHelpers.in_a_temporary_directory do |tmp_dir|
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                ::Bundler.instance_variable_set(:@root, tmp_dir)
                # Remove installed gems from the default Rubygems index
                ::Gem::Specification.all = []

                # Set auth details for GitHub
                ::Bundler.settings.set_command_option(
                  "github.com",
                  "x-access-token:#{github_access_token}"
                )

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
            updated_gemfile_content(gemfile)
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

          path_gemspecs.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitized_gemspec_content(file))
          end

          evaled_gemfiles.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, updated_gemfile_content(file))
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
            "='#{spec&.version || '0.0.1'}'"
          end
        end
      end
    end
  end
end
