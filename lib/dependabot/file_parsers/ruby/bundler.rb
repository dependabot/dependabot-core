# frozen_string_literal: true
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/file_fetchers/ruby/bundler"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Ruby
      class Bundler < Dependabot::FileParsers::Base
        def parse
          dependencies = gemfile_dependencies

          gemspec_dependencies.each do |dep|
            existing_dependency = dependencies.find { |d| d.name == dep.name }
            if existing_dependency
              dependencies[dependencies.index(existing_dependency)] =
                Dependency.new(
                  name: existing_dependency.name,
                  version: existing_dependency.version || dep.version,
                  requirements:
                    existing_dependency.requirements + dep.requirements,
                  package_manager: "bundler"
                )
            else
              dependencies << dep
            end
          end

          dependencies
        end

        private

        def gemfile_dependencies
          return [] unless gemfile
          parsed_gemfile.map do |dependency|
            Dependency.new(
              name: dependency.name,
              version: dependency_version(dependency.name)&.to_s,
              requirements: [{
                requirement: dependency.requirement.to_s,
                groups: dependency.groups,
                file: "Gemfile"
              }],
              package_manager: "bundler"
            )
          end.compact
        end

        def gemspec_dependencies
          return [] unless gemspec
          parsed_gemspec.dependencies.map do |dependency|
            Dependency.new(
              name: dependency.name,
              version: dependency_version(dependency.name)&.to_s,
              requirements: [{
                requirement: dependency.requirement.to_s,
                groups: dependency.runtime? ? ["runtime"] : ["development"],
                file: gemspec.name
              }],
              package_manager: "bundler"
            )
          end
        end

        def parsed_gemfile
          @parsed_gemfile ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))

                ::Bundler::Definition.build("Gemfile", nil, {}).
                  dependencies.
                  select(&:current_platform?).
                  # We can't dump gemspec sources, and we wouldn't bump them
                  # anyway, so we filter them out.
                  reject { |dep| dep.source.is_a?(::Bundler::Source::Gemspec) }
              end
            end
        rescue SharedHelpers::ChildProcessFailed => error
          msg = error.error_class + " with message: " +
                error.error_message.force_encoding("UTF-8").encode
          raise Dependabot::DependencyFileNotEvaluatable, msg
        end

        def parsed_gemspec
          @parsed_gemspec ||=
            SharedHelpers.in_a_temporary_directory do
              File.write(gemspec.name, sanitized_gemspec_content(gemspec))

              SharedHelpers.in_a_forked_process do
                ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))
                ::Bundler.load_gemspec_uncached(gemspec.name)
              end
            end
        rescue SharedHelpers::ChildProcessFailed => error
          msg = error.error_class + " with message: " + error.error_message
          raise Dependabot::DependencyFileNotEvaluatable, msg
        end

        def write_temporary_dependency_files
          File.write("Gemfile", gemfile.content)
          File.write("Gemfile.lock", lockfile.content) if lockfile

          if ruby_version_file
            path = ruby_version_file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, ruby_version_file.content)
          end

          gemspecs.compact.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitized_gemspec_content(file))
          end
        end

        def check_required_files
          file_names = dependency_files.map(&:name)

          return if file_names.any? do |name|
            name.end_with?(".gemspec") && !name.include?("/")
          end

          return if file_names.include?("Gemfile")

          raise "A gemspec or Gemfile must be provided!"
        end

        def gemspecs
          dependency_files.select { |f| f.name.end_with?(".gemspec") }
        end

        def ruby_version_file
          dependency_files.find { |f| f.name == ".ruby-version" }
        end

        def gemfile
          @gemfile ||= get_original_file("Gemfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Gemfile.lock")
        end

        def gemspec
          # The gemspec for this project will be at the top level
          @gemspec ||= gemspecs.find { |f| f.name.split("/").count == 1 }
        end

        def sanitized_gemspec_content(gemspec)
          gemspec_content = gemspec.content.gsub(/^\s*require.*$/, "")
          # No need to set the version correctly - this is just an update
          # check so we're not going to persist any changes to the lockfile.
          gemspec_content.gsub(/=.*VERSION.*$/, "= '0.0.1'")
        end

        def dependency_version(dependency_name)
          return unless lockfile
          @parsed_lockfile ||= ::Bundler::LockfileParser.new(lockfile.content)

          if dependency_name == "bundler"
            return Gem::Version.new(::Bundler::VERSION)
          end

          # The safe navigation operator is necessary because not all files in
          # the Gemfile will appear in the Gemfile.lock. For instance, if a gem
          # specifies `platform: [:windows]`, and the Gemfile.lock is generated
          # on a Linux machine, the gem will be not appear in the lockfile.
          @parsed_lockfile.specs.
            find { |spec| spec.name == dependency_name }&.
            version
        end
      end
    end
  end
end
