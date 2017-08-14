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
          dependencies.map do |dependency|
            # Ignore dependencies with multiple requirements, since they would
            # cause trouble at the gem update step. TODO: fix!
            next if dependency.requirement.requirements.count > 1

            # Ignore gems which appear in the Gemfile but not the Gemfile.lock.
            # For instance, if a gem specifies `platform: [:windows]`, and the
            # Gemfile.lock is generated on a Linux machine.
            next if dependency_version(dependency.name).nil?

            Dependency.new(
              name: dependency.name,
              version: dependency_version(dependency.name).to_s,
              requirement: dependency.requirement.to_s,
              package_manager: "bundler",
              groups: dependency.groups
            )
          end.compact
        end

        private

        def dependencies
          @dependencies ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))

                ::Bundler::Definition.build("Gemfile", "Gemfile.lock", {}).
                  dependencies.
                  # We can't dump gemspec sources, and we wouldn't bump them
                  # anyway, so we filter them out.
                  reject { |dep| dep.source.is_a?(::Bundler::Source::Gemspec) }
              end
            end
        end

        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
        end

        def required_files
          Dependabot::FileFetchers::Ruby::Bundler.required_files
        end

        def gemfile
          @gemfile ||= get_original_file("Gemfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Gemfile.lock")
        end

        # Parse the Gemfile.lock to get the gem version. Better than just
        # relying on the dependency's specified version, which may have had a
        # ~> matcher.
        def dependency_version(dependency_name)
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
