# frozen_string_literal: true
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/file_fetchers/ruby/gemspec"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Ruby
      class Gemspec < Dependabot::FileParsers::Base
        def parse
          parsed_gemspec.dependencies.map do |dependency|
            Dependency.new(
              name: dependency.name,
              requirement: dependency.requirement,
              package_manager: "gemspec"
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
          gemspec_content = gemspec.content.gsub(/^\s?require.*$/, "")
          gemspec_content.gsub(/[^_]?version\s*=.*VERSION.*$/) do |old_version|
            # No need to set the version correctly, and we have no way of
            # doing so anyway...
            old_version.sub(/=.*VERSION.*/, "= '0.0.1'")
          end
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
        end
      end
    end
  end
end
