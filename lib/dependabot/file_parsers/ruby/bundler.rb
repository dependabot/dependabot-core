# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Ruby
      class Bundler < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/ruby/bundler/dependency_set"
        require "dependabot/file_parsers/ruby/bundler/file_preparer"
        require "dependabot/file_parsers/ruby/bundler/gemfile_checker"

        EXPECTED_SOURCES = [
          NilClass,
          ::Bundler::Source::Rubygems,
          ::Bundler::Source::Git,
          ::Bundler::Source::Path,
          ::Bundler::Source::Gemspec,
          ::Bundler::Source::Metadata
        ].freeze

        def parse
          dependency_set = DependencySet.new
          dependency_set += gemfile_dependencies
          dependency_set += gemspec_dependencies
          dependency_set.dependencies
        end

        private

        def gemfile_dependencies
          dependencies = DependencySet.new

          return dependencies unless gemfile

          [gemfile, *evaled_gemfiles].each do |file|
            parsed_gemfile.each do |dep|
              next unless dependency_in_gemfile?(gemfile: file, dependency: dep)

              dependencies <<
                Dependency.new(
                  name: dep.name,
                  version: dependency_version(dep.name)&.to_s,
                  requirements: [{
                    requirement: dep.requirement.to_s,
                    groups: dep.groups,
                    source: source_for(dep),
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

          return dependencies unless gemspec

          parsed_gemspec.dependencies.each do |dependency|
            dependencies <<
              Dependency.new(
                name: dependency.name,
                version: dependency_version(dependency.name)&.to_s,
                requirements: [{
                  requirement: dependency.requirement.to_s,
                  groups: dependency.runtime? ? ["runtime"] : ["development"],
                  source: nil,
                  file: gemspec.name
                }],
                package_manager: "bundler"
              )
          end

          dependencies
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
              File.write(gemspec.name, gemspec.content)

              SharedHelpers.in_a_forked_process do
                ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))
                ::Bundler.load_gemspec_uncached(gemspec.name)
              end
            end
        rescue SharedHelpers::ChildProcessFailed => error
          msg = error.error_class + " with message: " + error.error_message
          raise Dependabot::DependencyFileNotEvaluatable, msg
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
        end

        def check_required_files
          file_names = dependency_files.map(&:name)

          return if file_names.any? do |name|
            name.end_with?(".gemspec") && !name.include?("/")
          end

          return if file_names.include?("Gemfile")

          raise "A gemspec or Gemfile must be provided!"
        end

        def source_for(dependency)
          source = dependency.source

          unless EXPECTED_SOURCES.any? { |s| source.instance_of?(s) }
            raise "Unexpected Ruby source: #{source}"
          end

          return nil if dependency.source.nil?
          details = { type: source.class.name.split("::").last.downcase }
          if source.is_a?(::Bundler::Source::Git)
            details[:url] = source.uri
            details[:branch] = source.branch || "master"
            details[:ref] = source.ref
          end
          details
        end

        def dependency_version(dependency_name)
          return unless lockfile
          @parsed_lockfile ||= ::Bundler::LockfileParser.new(lockfile.content)

          if dependency_name == "bundler"
            return Gem::Version.new(::Bundler::VERSION)
          end

          spec = @parsed_lockfile.specs.find { |s| s.name == dependency_name }

          # Not all files in the Gemfile will appear in the Gemfile.lock. For
          # instance, if a gem specifies `platform: [:windows]`, and the
          # Gemfile.lock is generated on a Linux machine, the gem will be not
          # appear in the lockfile.
          return unless spec

          # If the source is Git we're better off knowing the SHA-1 than the
          # version.
          if spec.source.instance_of?(::Bundler::Source::Git)
            return spec.source.revision
          end
          spec.version
        end

        def dependency_in_gemfile?(gemfile:, dependency:)
          GemfileChecker.new(
            dependency: dependency,
            gemfile: gemfile
          ).includes_dependency?
        end

        def gemfile
          @gemfile ||= get_original_file("Gemfile")
        end

        def evaled_gemfiles
          dependency_files.
            reject { |f| f.name.end_with?(".gemspec") }.
            reject { |f| f.name.end_with?(".lock") }.
            reject { |f| f.name.end_with?(".ruby-version") }.
            reject { |f| f.name == "Gemfile" }
        end

        def lockfile
          @lockfile ||= get_original_file("Gemfile.lock")
        end

        def gemspec
          # The gemspec for this project will be at the top level
          @gemspec ||= prepared_dependency_files.find do |file|
            file.name.match?(%r{^[^/]*\.gemspec$})
          end
        end
      end
    end
  end
end
