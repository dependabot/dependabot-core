# frozen_string_literal: true
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/file_fetchers/ruby/gemspec"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Ruby
      class Gemspec < Dependabot::FileParsers::Base
        def parse
          parsed_gemspec.dependencies.map do |dependency|
            Dependency.new(
              name: dependency.name,
              version: dependency.requirement.to_s,
              requirement: dependency.requirement.to_s,
              package_manager: "gemspec",
              groups: dependency.runtime? ? ["runtime"] : ["development"]
            )
          end
        end

        private

        def required_files
          Dependabot::FileFetchers::Ruby::Gemspec.required_files
        end

        def gemspec
          dependency_files.find { |f| f.name.end_with?(".gemspec") }
        end

        def sanitized_gemspec
          gemspec_content = gemspec.content.gsub(/^\s*require.*$/, "")
          # No need to set the version correctly - this is just an update
          # check so we're not going to persist any changes to the lockfile.
          gemspec_content.gsub(/=.*VERSION.*$/, "= '0.0.1'")
        end

        def parsed_gemspec
          @parsed_gemspec ||=
            SharedHelpers.in_a_temporary_directory do
              File.write(gemspec.name, sanitized_gemspec)

              SharedHelpers.in_a_forked_process do
                ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))
                ::Bundler.load_gemspec_uncached(gemspec.name)
              end
            end
        rescue SharedHelpers::ChildProcessFailed => error
          msg = error.error_class + " with message: " + error.error_message
          raise Dependabot::DependencyFileNotEvaluatable, msg
        end
      end
    end
  end
end
