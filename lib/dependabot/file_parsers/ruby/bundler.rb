# frozen_string_literal: true

require "parser/current"

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Ruby
      class Bundler < Dependabot::FileParsers::Base
        EXPECTED_SOURCES = [
          NilClass,
          ::Bundler::Source::Rubygems,
          ::Bundler::Source::Git,
          ::Bundler::Source::Path,
          ::Bundler::Source::Gemspec,
          ::Bundler::Source::Metadata
        ].freeze

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
          all_dependencies = parsed_gemfile.map do |dependency|
            Dependency.new(
              name: dependency.name,
              version: dependency_version(dependency.name)&.to_s,
              requirements: [{
                requirement: dependency.requirement.to_s,
                groups: dependency.groups,
                source: source_for(dependency),
                file: "Gemfile"
              }],
              package_manager: "bundler"
            )
          end.compact

          # Filter out dependencies that only appear in the gemspec
          all_dependencies.select { |dep| gemfile_includes_dependency?(dep) }
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
                source: nil,
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

        def gemfile_includes_dependency?(dependency)
          GemfileDependencyChecker.new(
            dependency: dependency,
            gemfile: gemfile
          ).includes_dependency?
        end

        class GemfileDependencyChecker
          def initialize(dependency:, gemfile:)
            @dependency = dependency
            @gemfile = gemfile
          end

          def includes_dependency?
            Parser::CurrentRuby.parse(gemfile.content).children.any? do |node|
              deep_check_for_gem(node)
            end
          end

          private

          attr_reader :dependency, :gemfile

          def deep_check_for_gem(node)
            return true if declares_targeted_gem?(node)
            return false unless node.is_a?(Parser::AST::Node)
            node.children.any? do |child_node|
              deep_check_for_gem(child_node)
            end
          end

          def declares_targeted_gem?(node)
            return false unless node.is_a?(Parser::AST::Node)
            return false unless node.children[1] == :gem
            node.children[2].children.first == dependency.name
          end
        end
      end
    end
  end
end
