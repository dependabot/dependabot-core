# frozen_string_literal: true

require "bundler"

require "bundler_definition_ruby_version_patch"
require "bundler_definition_bundler_version_patch"
require "bundler_git_source_patch"

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/file_updaters/base"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler < Dependabot::FileUpdaters::Base
        require_relative "bundler/gemspec_sanitizer"
        require_relative "bundler/git_pin_replacer"
        require_relative "bundler/git_source_remover"
        require_relative "bundler/requirement_replacer"
        require_relative "bundler/gemspec_dependency_name_finder"

        LOCKFILE_ENDING = /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m
        GEM_NOT_FOUND_ERROR_REGEX = /locked to (?<name>[^\s]+) \(/

        def self.updated_files_regex
          [/^Gemfile$/, /^Gemfile\.lock$/, %r{^[^/]*\.gemspec$}]
        end

        def updated_dependency_files
          updated_files = []

          if gemfile && file_changed?(gemfile)
            updated_files <<
              updated_file(
                file: gemfile,
                content: updated_gemfile_content(gemfile)
              )
          end

          if lockfile && dependencies.any?(&:appears_in_lockfile?)
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          top_level_gemspecs.each do |file|
            next unless file_changed?(file)
            updated_files <<
              updated_file(file: file, content: updated_gemspec_content(file))
          end

          evaled_gemfiles.each do |file|
            next unless file_changed?(file)
            updated_files <<
              updated_file(file: file, content: updated_gemfile_content(file))
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

        def remove_git_source?(dependency)
          old_gemfile_req =
            dependency.previous_requirements.find { |f| f[:file] == "Gemfile" }
          return false unless old_gemfile_req&.dig(:source, :type) == "git"

          new_gemfile_req =
            dependency.requirements.find { |f| f[:file] == "Gemfile" }

          new_gemfile_req[:source].nil?
        end

        def update_git_pin?(dependency)
          new_gemfile_req =
            dependency.requirements.find { |f| f[:file] == "Gemfile" }
          return false unless new_gemfile_req&.dig(:source, :type) == "git"

          # If the new requirement is a git dependency with a ref then there's
          # no harm in doing an update
          new_gemfile_req.dig(:source, :ref)
        end

        def updated_gemfile_content(file)
          content = file.content

          dependencies.each do |dependency|
            content =
              replace_gemfile_version_requirement(dependency, file, content)
            if remove_git_source?(dependency)
              content = remove_gemfile_git_source(dependency, content)
            end
            if update_git_pin?(dependency)
              content = update_gemfile_git_pin(dependency, file, content)
            end
          end

          content
        end

        def updated_gemspec_content(gemspec)
          content = gemspec.content

          dependencies.each do |dependency|
            content = replace_gemspec_version_requirement(
              gemspec, dependency, content
            )
          end

          content
        end

        def replace_gemfile_version_requirement(dependency, file, content)
          return content unless requirement_changed?(file, dependency)

          updated_requirement =
            dependency.requirements.
            find { |r| r[:file] == file.name }.
            fetch(:requirement)

          RequirementReplacer.new(
            dependency: dependency,
            file_type: :gemfile,
            updated_requirement: updated_requirement
          ).rewrite(content)
        end

        def remove_gemfile_git_source(dependency, content)
          GitSourceRemover.new(dependency: dependency).rewrite(content)
        end

        def update_gemfile_git_pin(dependency, file, content)
          new_pin =
            dependency.requirements.
            find { |f| f[:file] == file.name }.
            fetch(:source).fetch(:ref)

          GitPinReplacer.
            new(dependency: dependency, new_pin: new_pin).
            rewrite(content)
        end

        def replace_gemspec_version_requirement(gemspec, dependency, content)
          return content unless requirement_changed?(gemspec, dependency)

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
          @updated_lockfile_content ||=
            begin
              updated_content = build_updated_lockfile
              if lockfile.content == updated_content
                raise "Expected content to change!"
              end
              updated_content
            end
        end

        def build_updated_lockfile
          lockfile_body =
            SharedHelpers.in_a_temporary_directory do |tmp_dir|
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                ::Bundler.instance_variable_set(:@root, tmp_dir)
                # Remove installed gems from the default Rubygems index
                ::Gem::Specification.all = []

                # Set auth details
                credentials.each do |cred|
                  ::Bundler.settings.set_command_option(
                    cred["host"],
                    cred["token"] || "#{cred['username']}:#{cred['password']}"
                  )
                end

                generate_lockfile
              end
            end
          post_process_lockfile(lockfile_body)
        end

        def generate_lockfile
          dependencies_to_unlock = dependencies.map(&:name)

          begin
            definition = build_definition(dependencies_to_unlock)
            definition.resolve_remotely!
            definition.to_lock
          rescue ::Bundler::GemNotFound => error
            raise unless error.message.match?(GEM_NOT_FOUND_ERROR_REGEX)
            gem_name = error.message.match(GEM_NOT_FOUND_ERROR_REGEX).
                       named_captures["name"]
            raise if dependencies_to_unlock.include?(gem_name)
            dependencies_to_unlock << gem_name
            retry
          end
        end

        def build_definition(dependencies_to_unlock)
          ::Bundler::Definition.build(
            "Gemfile",
            "Gemfile.lock",
            gems: dependencies_to_unlock
          )
        end

        def write_temporary_dependency_files
          File.write("Gemfile", updated_gemfile_content(gemfile))
          File.write("Gemfile.lock", lockfile.content)

          top_level_gemspecs.each do |gemspec|
            File.write(
              gemspec.name,
              sanitized_gemspec_content(updated_gemspec_content(gemspec))
            )
          end

          write_ruby_version_file
          write_path_gemspecs
          write_imported_ruby_files

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

        def write_path_gemspecs
          path_gemspecs.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitized_gemspec_content(file.content))
          end
        end

        def write_imported_ruby_files
          imported_ruby_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
        end

        def path_gemspecs
          all = dependency_files.select { |f| f.name.end_with?(".gemspec") }
          all - top_level_gemspecs
        end

        def imported_ruby_files
          dependency_files.select { |f| f.name.end_with?(".rb") }
        end

        def top_level_gemspecs
          dependency_files.select { |f| f.name.match?(%r{^[^/]*\.gemspec$}) }
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

        def sanitized_gemspec_content(gemspec_content)
          new_version = replacement_version_for_gemspec(gemspec_content)

          GemspecSanitizer.
            new(replacement_version: new_version).
            rewrite(gemspec_content)
        end

        def replacement_version_for_gemspec(gemspec_content)
          return "0.0.1" unless lockfile

          parsed_lockfile = ::Bundler::LockfileParser.new(lockfile.content)
          gem_name =
            GemspecDependencyNameFinder.new(gemspec_content: gemspec_content).
            dependency_name

          return "0.0.1" unless gem_name
          spec = parsed_lockfile.specs.find { |s| s.name == gem_name }
          spec&.version || "0.0.1"
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
