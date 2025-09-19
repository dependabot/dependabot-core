# typed: strict
# frozen_string_literal: true

require "bundler"
require "sorbet-runtime"

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/bundler/file_updater"
require "dependabot/bundler/cached_lockfile_parser"
require "dependabot/bundler/native_helpers"
require "dependabot/bundler/helpers"

module Dependabot
  module Bundler
    class FileUpdater
      class LockfileUpdater
        extend T::Sig

        require_relative "gemfile_updater"
        require_relative "gemspec_updater"
        require_relative "gemspec_sanitizer"
        require_relative "gemspec_dependency_name_finder"
        require_relative "ruby_requirement_setter"

        LOCKFILE_ENDING = /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m
        GIT_DEPENDENCIES_SECTION = /GIT\n.*?\n\n(?!GIT)/m
        GIT_DEPENDENCY_DETAILS = /GIT\n.*?\n\n/m

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            options: T::Hash[Symbol, T.untyped],
            repo_contents_path: T.nilable(String)
          ).void
        end
        def initialize(
          dependencies:,
          dependency_files:,
          credentials:,
          options:,
          repo_contents_path: nil
        )
          @dependencies = T.let(dependencies, T::Array[Dependabot::Dependency])
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @repo_contents_path = T.let(repo_contents_path, T.nilable(String))
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
          @options = T.let(options, T::Hash[Symbol, T.untyped])
          @updated_lockfile_content = T.let(nil, T.nilable(String))
          @gemfile = T.let(nil, T.nilable(Dependabot::DependencyFile))
          @lockfile = T.let(nil, T.nilable(Dependabot::DependencyFile))
          @evaled_gemfiles = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @bundler_version = T.let(nil, T.nilable(String))
        end

        # Can't be a constant because some of these don't exist in bundler
        # 1.15, which Heroku uses, which causes an exception on boot.
        sig { returns(T::Array[T.class_of(::Bundler::Source::Path)]) }
        def gemspec_sources
          [
            ::Bundler::Source::Path,
            ::Bundler::Source::Gemspec
          ]
        end

        sig { returns(String) }
        def updated_lockfile_content
          @updated_lockfile_content ||=
            begin
              updated_content = build_updated_lockfile

              raise "Expected content to change!" if T.must(lockfile).content == updated_content

              updated_content
            end
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :options

        sig { returns(String) }
        def build_updated_lockfile
          base_dir = T.must(dependency_files.first).directory
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
                  gemfile_name: T.must(gemfile).name,
                  lockfile_name: T.must(lockfile).name,
                  dir: tmp_dir,
                  credentials: credentials,
                  dependencies: dependencies.map(&:to_h)
                }
              )
            end
          post_process_lockfile(lockfile_body)
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise Dependabot::DependencyFileNotResolvable, e.message if e.error_class == "Bundler::SolveFailure"

          raise
        end

        sig { void }
        def write_temporary_dependency_files
          File.write(T.must(gemfile).name, prepared_gemfile_content(T.must(gemfile)))
          File.write(T.must(lockfile).name, sanitized_lockfile_body)

          write_gemspecs(top_level_gemspecs)
          write_ruby_version_file
          write_tool_versions_file
          write_gemspecs(path_gemspecs)
          write_specification_files
          write_imported_ruby_files

          evaled_gemfiles.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, updated_gemfile_content(file))
          end
        end

        sig { void }
        def write_ruby_version_file
          return unless ruby_version_file

          path = T.must(ruby_version_file).name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, T.must(ruby_version_file).content)
        end

        sig { void }
        def write_tool_versions_file
          return unless tool_versions_file

          path = T.must(tool_versions_file).name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, T.must(tool_versions_file).content)
        end

        sig { params(files: T::Array[Dependabot::DependencyFile]).void }
        def write_gemspecs(files)
          files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            updated_content = updated_gemspec_content(file)
            File.write(path, sanitized_gemspec_content(path, updated_content))
          end
        end

        sig { void }
        def write_specification_files
          specification_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
        end

        sig { void }
        def write_imported_ruby_files
          imported_ruby_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def path_gemspecs
          all = dependency_files.select { |f| f.name.end_with?(".gemspec") }
          all - top_level_gemspecs
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def imported_ruby_files
          dependency_files
            .select { |f| f.name.end_with?(".rb") }
            .reject { |f| f.name == "gems.rb" }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def top_level_gemspecs
          dependency_files
            .select { |file| file.name.end_with?(".gemspec") && Pathname.new(file.name).dirname.to_s == "." }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def ruby_version_file
          dependency_files.find { |f| f.name == ".ruby-version" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def tool_versions_file
          dependency_files.find { |f| f.name == ".tool-versions" }
        end

        sig { params(lockfile_body: String).returns(String) }
        def post_process_lockfile(lockfile_body)
          lockfile_body = reorder_git_dependencies(lockfile_body)
          replace_lockfile_ending(lockfile_body)
        end

        sig { params(lockfile_body: String).returns(String) }
        def reorder_git_dependencies(lockfile_body)
          new_section = lockfile_body.match(GIT_DEPENDENCIES_SECTION)&.to_s
          lockfile_content = T.must(lockfile).content
          old_section = lockfile_content&.match(GIT_DEPENDENCIES_SECTION)&.to_s

          return lockfile_body unless new_section && old_section

          new_deps = new_section.scan(GIT_DEPENDENCY_DETAILS)
          old_deps = old_section.scan(GIT_DEPENDENCY_DETAILS)

          return lockfile_body unless new_deps.count == old_deps.count

          reordered_new_section = new_deps.sort_by do |new_dep_details|
            dep_string = T.cast(new_dep_details, String)
            match_result = dep_string.match(/remote: (?<remote>.*\n)/)
            remote = match_result ? match_result[:remote] : ""
            i = old_deps.index { |details| details.include?(T.must(remote)) }

            # If this dependency isn't in the old lockfile then we can't rely
            # on that (presumably outdated) lockfile to do reordering.
            # Instead, we just return the default-ordered content just
            # generated.
            return lockfile_body unless i

            i
          end.join

          lockfile_body.gsub(new_section, reordered_new_section)
        end

        sig { params(lockfile_body: String).returns(String) }
        def replace_lockfile_ending(lockfile_body)
          # Re-add the old `BUNDLED WITH` version (and remove the RUBY VERSION
          # if it wasn't previously present in the lockfile)
          lockfile_content = T.must(lockfile).content
          lockfile_body.gsub(
            LOCKFILE_ENDING,
            lockfile_content&.match(LOCKFILE_ENDING)&.[](:ending) || "\n"
          )
        end

        sig { params(path: String, gemspec_content: String).returns(String) }
        def sanitized_gemspec_content(path, gemspec_content)
          new_version = replacement_version_for_gemspec(path, gemspec_content)

          GemspecSanitizer
            .new(replacement_version: new_version)
            .rewrite(gemspec_content)
        end

        sig { params(path: String, gemspec_content: String).returns(String) }
        def replacement_version_for_gemspec(path, gemspec_content)
          return "0.0.1" unless lockfile

          gem_name =
            GemspecDependencyNameFinder.new(gemspec_content: gemspec_content)
                                       .dependency_name || File.basename(path, ".gemspec")

          gemspec_specs =
            CachedLockfileParser.parse(sanitized_lockfile_body).specs
                                .select { |s| s.name == gem_name && gemspec_sources.include?(s.source.class) }

          gemspec_specs.first&.version&.to_s || "0.0.1"
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def prepared_gemfile_content(file)
          content = updated_gemfile_content(file)

          top_level_gemspecs.each do |gs|
            content = RubyRequirementSetter.new(gemspec: gs).rewrite(content)
          end

          content
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def updated_gemfile_content(file)
          GemfileUpdater.new(
            dependencies: dependencies,
            gemfile: file
          ).updated_gemfile_content
        end

        sig { params(gemspec: Dependabot::DependencyFile).returns(String) }
        def updated_gemspec_content(gemspec)
          GemspecUpdater.new(
            dependencies: dependencies,
            gemspec: gemspec
          ).updated_gemspec_content
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def gemfile
          @gemfile ||= dependency_files.find { |f| f.name == "Gemfile" } ||
                       dependency_files.find { |f| f.name == "gems.rb" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def lockfile
          @lockfile ||=
            dependency_files.find { |f| f.name == "Gemfile.lock" } ||
            dependency_files.find { |f| f.name == "gems.locked" }
        end

        # TODO: Stop sanitizing the lockfile once we have bundler 2 installed
        sig { returns(String) }
        def sanitized_lockfile_body
          content = T.must(lockfile).content
          T.must(content).gsub(LOCKFILE_ENDING, "")
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def evaled_gemfiles
          @evaled_gemfiles ||=
            dependency_files
            .reject { |f| f.name.end_with?(".gemspec") }
            .reject { |f| f.name.end_with?(".specification") }
            .reject { |f| f.name.end_with?(".lock") }
            .reject { |f| f.name == "Gemfile" }
            .reject { |f| f.name == "gems.rb" }
            .reject { |f| f.name == "gems.locked" }
            .reject(&:support_file?)
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def specification_files
          dependency_files.select { |f| f.name.end_with?(".specification") }
        end

        sig { returns(String) }
        def bundler_version
          @bundler_version ||= Helpers.bundler_version(lockfile)
        end
      end
    end
  end
end
