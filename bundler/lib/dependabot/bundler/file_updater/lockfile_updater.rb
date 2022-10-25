# frozen_string_literal: true

require "bundler"

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/bundler/file_updater"
require "dependabot/bundler/native_helpers"
require "dependabot/bundler/helpers"

module Dependabot
  module Bundler
    class FileUpdater
      class LockfileUpdater
        require_relative "gemfile_updater"
        require_relative "gemspec_updater"
        require_relative "gemspec_sanitizer"
        require_relative "gemspec_dependency_name_finder"
        require_relative "ruby_requirement_setter"

        LOCKFILE_ENDING = /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m
        GIT_DEPENDENCIES_SECTION = /GIT\n.*?\n\n(?!GIT)/m
        GIT_DEPENDENCY_DETAILS = /GIT\n.*?\n\n/m

        # Can't be a constant because some of these don't exist in bundler
        # 1.15, which Heroku uses, which causes an exception on boot.
        def gemspec_sources
          [
            ::Bundler::Source::Path,
            ::Bundler::Source::Gemspec
          ]
        end

        def initialize(dependencies:, dependency_files:,
                       repo_contents_path: nil, credentials:, options:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
          @options = options
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            begin
              updated_content = build_updated_lockfile

              raise "Expected content to change!" if lockfile.content == updated_content

              updated_content
            end
        end

        private

        attr_reader :dependencies, :dependency_files, :repo_contents_path,
                    :credentials, :options

        def build_updated_lockfile
          base_dir = dependency_files.first.directory
          lockfile_body =
            SharedHelpers.in_a_temporary_repo_directory(
              base_dir,
              repo_contents_path
            ) do |tmp_dir|
              write_temporary_dependency_files

              NativeHelpers.run_bundler_subprocess(
                bundler_version: bundler_version,
                function: "update_lockfile",
                options: options,
                args: {
                  gemfile_name: gemfile.name,
                  lockfile_name: lockfile.name,
                  dir: tmp_dir,
                  credentials: credentials,
                  dependencies: dependencies.map(&:to_h)
                }
              )
            end
          post_process_lockfile(lockfile_body)
        end

        def write_temporary_dependency_files
          File.write(gemfile.name, prepared_gemfile_content(gemfile))
          File.write(lockfile.name, sanitized_lockfile_body)

          top_level_gemspecs.each do |gemspec|
            path = gemspec.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            updated_content = updated_gemspec_content(gemspec)
            File.write(path, sanitized_gemspec_content(updated_content))
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

          specification_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
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
          dependency_files.
            select { |f| f.name.end_with?(".rb") }.
            reject { |f| f.name == "gems.rb" }
        end

        def top_level_gemspecs
          dependency_files.
            select { |file| file.name.end_with?(".gemspec") }.
            reject(&:support_file?)
        end

        def ruby_version_file
          dependency_files.find { |f| f.name == ".ruby-version" }
        end

        def post_process_lockfile(lockfile_body)
          lockfile_body = reorder_git_dependencies(lockfile_body)
          replace_lockfile_ending(lockfile_body)
        end

        def reorder_git_dependencies(lockfile_body)
          new_section = lockfile_body.match(GIT_DEPENDENCIES_SECTION)&.to_s
          old_section = lockfile.content.match(GIT_DEPENDENCIES_SECTION)&.to_s

          return lockfile_body unless new_section && old_section

          new_deps = new_section.scan(GIT_DEPENDENCY_DETAILS)
          old_deps = old_section.scan(GIT_DEPENDENCY_DETAILS)

          return lockfile_body unless new_deps.count == old_deps.count

          reordered_new_section = new_deps.sort_by do |new_dep_details|
            remote = new_dep_details.match(/remote: (?<remote>.*\n)/)[:remote]
            i = old_deps.index { |details| details.include?(remote) }

            # If this dependency isn't in the old lockfile then we can't rely
            # on that (presumably outdated) lockfile to do reordering.
            # Instead, we just return the default-ordered content just
            # generated.
            return lockfile_body unless i

            i
          end.join

          lockfile_body.gsub(new_section, reordered_new_section)
        end

        def replace_lockfile_ending(lockfile_body)
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

        # rubocop:disable Metrics/PerceivedComplexity
        def replacement_version_for_gemspec(gemspec_content)
          return "0.0.1" unless lockfile

          gemspec_specs =
            ::Bundler::LockfileParser.new(sanitized_lockfile_body).specs.
            select { |s| gemspec_sources.include?(s.source.class) }

          gem_name =
            GemspecDependencyNameFinder.new(gemspec_content: gemspec_content).
            dependency_name

          return gemspec_specs.first&.version || "0.0.1" unless gem_name

          spec = gemspec_specs.find { |s| s.name == gem_name }
          spec&.version || gemspec_specs.first&.version || "0.0.1"
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def prepared_gemfile_content(file)
          content = updated_gemfile_content(file)

          top_level_gemspecs.each do |gs|
            content = RubyRequirementSetter.new(gemspec: gs).rewrite(content)
          end

          content
        end

        def updated_gemfile_content(file)
          GemfileUpdater.new(
            dependencies: dependencies,
            gemfile: file
          ).updated_gemfile_content
        end

        def updated_gemspec_content(gemspec)
          GemspecUpdater.new(
            dependencies: dependencies,
            gemspec: gemspec
          ).updated_gemspec_content
        end

        def gemfile
          @gemfile ||= dependency_files.find { |f| f.name == "Gemfile" } ||
                       dependency_files.find { |f| f.name == "gems.rb" }
        end

        def lockfile
          @lockfile ||=
            dependency_files.find { |f| f.name == "Gemfile.lock" } ||
            dependency_files.find { |f| f.name == "gems.locked" }
        end

        # TODO: Stop sanitizing the lockfile once we have bundler 2 installed
        def sanitized_lockfile_body
          lockfile.content.gsub(LOCKFILE_ENDING, "")
        end

        def evaled_gemfiles
          @evaled_gemfiles ||=
            dependency_files.
            reject { |f| f.name.end_with?(".gemspec") }.
            reject { |f| f.name.end_with?(".specification") }.
            reject { |f| f.name.end_with?(".lock") }.
            reject { |f| f.name.end_with?(".ruby-version") }.
            reject { |f| f.name == "Gemfile" }.
            reject { |f| f.name == "gems.rb" }.
            reject { |f| f.name == "gems.locked" }.
            reject(&:support_file?)
        end

        def specification_files
          dependency_files.select { |f| f.name.end_with?(".specification") }
        end

        def bundler_version
          @bundler_version ||= Helpers.bundler_version(lockfile)
        end
      end
    end
  end
end
