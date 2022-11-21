# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/bundler/file_updater/lockfile_updater"
require "dependabot/bundler/native_helpers"
require "dependabot/bundler/helpers"
require "dependabot/bundler/version"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Bundler
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"
      require "dependabot/bundler/file_parser/file_preparer"
      require "dependabot/bundler/file_parser/gemfile_declaration_finder"
      require "dependabot/bundler/file_parser/gemspec_declaration_finder"

      def parse
        dependency_set = DependencySet.new
        dependency_set += gemfile_dependencies
        dependency_set += gemspec_dependencies
        dependency_set += lockfile_dependencies
        check_external_code(dependency_set.dependencies)
        instrument_package_manager_version
        dependency_set.dependencies
      end

      private

      def check_external_code(dependencies)
        return unless @reject_external_code
        return unless git_source?(dependencies)

        # A git source dependency might contain a .gemspec that is evaluated
        raise ::Dependabot::UnexpectedExternalCode
      end

      def git_source?(dependencies)
        dependencies.any? do |dep|
          dep.requirements.any? { |req| req.fetch(:source)&.fetch(:type) == "git" }
        end
      end

      def instrument_package_manager_version
        version = Helpers.detected_bundler_version(lockfile)
        Dependabot.instrument(
          Notifications::FILE_PARSER_PACKAGE_MANAGER_VERSION_PARSED,
          ecosystem: "bundler",
          package_managers: {
            "bundler" => version
          }
        )
      end

      def gemfile_dependencies
        dependencies = DependencySet.new

        return dependencies unless gemfile

        [gemfile, *evaled_gemfiles].each do |file|
          gemfile_declaration_finder = GemfileDeclarationFinder.new(gemfile: file)

          parsed_gemfile.each do |dep|
            next unless gemfile_declaration_finder.gemfile_includes_dependency?(dep)

            dependencies <<
              Dependency.new(
                name: dep.fetch("name"),
                version: dependency_version(dep.fetch("name"))&.to_s,
                requirements: [{
                  requirement: gemfile_declaration_finder.enhanced_req_string(dep),
                  groups: dep.fetch("groups").map(&:to_sym),
                  source: dep.fetch("source")&.transform_keys(&:to_sym),
                  file: file.name
                }],
                package_manager: "bundler"
              )
          end
        end

        dependencies
      end

      def gemspec_dependencies
        dependencies = DependencySet.new

        gemspecs.each do |gemspec|
          gemspec_declaration_finder = GemspecDeclarationFinder.new(gemspec: gemspec)

          parsed_gemspec(gemspec).each do |dependency|
            next unless gemspec_declaration_finder.gemspec_includes_dependency?(dependency)

            dependencies <<
              Dependency.new(
                name: dependency.fetch("name"),
                version: dependency_version(dependency.fetch("name"))&.to_s,
                requirements: [{
                  requirement: dependency.fetch("requirement").to_s,
                  groups: if dependency.fetch("type") == "runtime"
                            ["runtime"]
                          else
                            ["development"]
                          end,
                  source: dependency.fetch("source")&.transform_keys(&:to_sym),
                  file: gemspec.name
                }],
                package_manager: "bundler"
              )
          end
        end

        dependencies
      end

      def lockfile_dependencies
        dependencies = DependencySet.new

        return dependencies unless lockfile

        # Create a DependencySet where each element has no requirement. Any
        # requirements will be added when combining the DependencySet with
        # other DependencySets.
        parsed_lockfile.specs.each do |dependency|
          next if dependency.source.is_a?(::Bundler::Source::Path)

          dependencies <<
            Dependency.new(
              name: dependency.name,
              version: dependency_version(dependency.name)&.to_s,
              requirements: [],
              package_manager: "bundler",
              subdependency_metadata: [{
                production: production_dep_names.include?(dependency.name)
              }]
            )
        end

        dependencies
      end

      def parsed_gemfile
        @parsed_gemfile ||=
          SharedHelpers.in_a_temporary_repo_directory(base_directory,
                                                      repo_contents_path) do
            write_temporary_dependency_files

            NativeHelpers.run_bundler_subprocess(
              bundler_version: bundler_version,
              function: "parsed_gemfile",
              options: options,
              args: {
                gemfile_name: gemfile.name,
                lockfile_name: lockfile&.name,
                dir: Dir.pwd
              }
            )
          end
      rescue SharedHelpers::HelperSubprocessFailed => e
        handle_eval_error(e) if e.error_class == "JSON::ParserError"

        msg = e.error_class + " with message: " +
              e.message.force_encoding("UTF-8").encode
        raise Dependabot::DependencyFileNotEvaluatable, msg
      end

      def handle_eval_error(err)
        msg = "Error evaluating your dependency files: #{err.message}"
        raise Dependabot::DependencyFileNotEvaluatable, msg
      end

      def parsed_gemspec(file)
        @parsed_gemspecs ||= {}
        @parsed_gemspecs[file.name] ||=
          SharedHelpers.in_a_temporary_repo_directory(base_directory,
                                                      repo_contents_path) do
            write_temporary_dependency_files

            NativeHelpers.run_bundler_subprocess(
              bundler_version: bundler_version,
              function: "parsed_gemspec",
              options: options,
              args: {
                gemspec_name: file.name,
                lockfile_name: lockfile&.name,
                dir: Dir.pwd
              }
            )
          end
      rescue SharedHelpers::HelperSubprocessFailed => e
        msg = e.error_class + " with message: " + e.message
        raise Dependabot::DependencyFileNotEvaluatable, msg
      end

      def base_directory
        dependency_files.first.directory
      end

      def prepared_dependency_files
        @prepared_dependency_files ||=
          FilePreparer.new(dependency_files: dependency_files).
          prepared_dependency_files
      end

      def write_temporary_dependency_files
        prepared_dependency_files.each do |file|
          path = file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, file.content)
        end

        File.write(lockfile.name, sanitized_lockfile_content) if lockfile
      end

      def check_required_files
        file_names = dependency_files.map(&:name)

        return if file_names.any? do |name|
          name.end_with?(".gemspec") && !name.include?("/")
        end

        return if gemfile

        raise "A gemspec or Gemfile must be provided!"
      end

      def dependency_version(dependency_name)
        return unless lockfile

        spec = parsed_lockfile.specs.find { |s| s.name == dependency_name }

        # Not all files in the Gemfile will appear in the Gemfile.lock. For
        # instance, if a gem specifies `platform: [:windows]`, and the
        # Gemfile.lock is generated on a Linux machine, the gem will be not
        # appear in the lockfile.
        return unless spec

        # If the source is Git we're better off knowing the SHA-1 than the
        # version.
        return spec.source.revision if spec.source.instance_of?(::Bundler::Source::Git)

        spec.version
      end

      def gemfile
        @gemfile ||= get_original_file("Gemfile") ||
                     get_original_file("gems.rb")
      end

      def evaled_gemfiles
        dependency_files.
          reject { |f| f.name.end_with?(".gemspec") }.
          reject { |f| f.name.end_with?(".specification") }.
          reject { |f| f.name.end_with?(".lock") }.
          reject { |f| f.name.end_with?(".ruby-version") }.
          reject { |f| f.name == "Gemfile" }.
          reject { |f| f.name == "gems.rb" }.
          reject { |f| f.name == "gems.locked" }
      end

      def lockfile
        @lockfile ||= get_original_file("Gemfile.lock") ||
                      get_original_file("gems.locked")
      end

      def parsed_lockfile
        @parsed_lockfile ||=
          ::Bundler::LockfileParser.new(sanitized_lockfile_content)
      end

      def production_dep_names
        @production_dep_names ||=
          (gemfile_dependencies + gemspec_dependencies).dependencies.
          select { |dep| production?(dep) }.
          flat_map { |dep| expanded_dependency_names(dep) }.
          uniq
      end

      def expanded_dependency_names(dep)
        spec = parsed_lockfile.specs.find { |s| s.name == dep.name }
        return [dep.name] unless spec

        [
          dep.name,
          *spec.dependencies.flat_map { |d| expanded_dependency_names(d) }
        ]
      end

      def production?(dependency)
        groups = dependency.requirements.
                 flat_map { |r| r.fetch(:groups) }.
                 map(&:to_s)

        return true if groups.empty?
        return true if groups.include?("runtime")
        return true if groups.include?("default")

        groups.any? { |g| g.include?("prod") }
      end

      # TODO: Stop sanitizing the lockfile once we have bundler 2 installed
      def sanitized_lockfile_content
        regex = FileUpdater::LockfileUpdater::LOCKFILE_ENDING
        lockfile.content.gsub(regex, "")
      end

      def gemspecs
        # Path gemspecs are excluded (they're supporting files)
        @gemspecs ||= prepared_dependency_files.
                      select { |file| file.name.end_with?(".gemspec") }.
                      reject(&:support_file?)
      end

      def imported_ruby_files
        dependency_files.
          select { |f| f.name.end_with?(".rb") }.
          reject { |f| f.name == "gems.rb" }
      end

      def bundler_version
        @bundler_version ||= Helpers.bundler_version(lockfile)
      end
    end
  end
end

Dependabot::FileParsers.register("bundler", Dependabot::Bundler::FileParser)
