# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/shared_helpers"
require "dependabot/python/file_parser"
require "dependabot/python/native_helpers"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileParser
      class SetupFileParser
        INSTALL_REQUIRES_REGEX = /install_requires\s*=\s*\[/m.freeze
        SETUP_REQUIRES_REGEX = /setup_requires\s*=\s*\[/m.freeze
        TESTS_REQUIRE_REGEX = /tests_require\s*=\s*\[/m.freeze
        EXTRAS_REQUIRE_REGEX = /extras_require\s*=\s*\{/m.freeze

        CLOSING_BRACKET = { "[" => "]", "{" => "}" }.freeze

        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def dependency_set
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          parsed_setup_file.each do |dep|
            # If a requirement has a `<` or `<=` marker then updating it is
            # probably blocked. Ignore it.
            next if dep["markers"].include?("<")

            # If the requirement is our inserted version, ignore it
            # (we wouldn't be able to update it)
            next if dep["version"] == "0.0.1+dependabot"

            dependencies <<
              Dependency.new(
                name: normalised_name(dep["name"], dep["extras"]),
                version: dep["version"]&.include?("*") ? nil : dep["version"],
                requirements: [{
                  requirement: dep["requirement"],
                  file: Pathname.new(dep["file"]).cleanpath.to_path,
                  source: nil,
                  groups: [dep["requirement_type"]]
                }],
                package_manager: "pip"
              )
          end
          dependencies
        end

        private

        attr_reader :dependency_files

        def parsed_setup_file
          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files

            requirements = SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python #{NativeHelpers.python_helper_path}",
              function: "parse_setup",
              args: [Dir.pwd]
            )

            check_requirements(requirements)
            requirements
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise Dependabot::DependencyFileNotEvaluatable, e.message if e.message.start_with?("InstallationError")

          return [] unless setup_file

          parsed_sanitized_setup_file
        end

        def parsed_sanitized_setup_file
          SharedHelpers.in_a_temporary_directory do
            write_sanitized_setup_file

            requirements = SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python #{NativeHelpers.python_helper_path}",
              function: "parse_setup",
              args: [Dir.pwd]
            )

            check_requirements(requirements)
            requirements
          end
        rescue SharedHelpers::HelperSubprocessFailed
          # Assume there are no dependencies in setup.py files that fail to
          # parse. This isn't ideal, and we should continue to improve
          # parsing, but there are a *lot* of things that can go wrong at
          # the moment!
          []
        end

        def check_requirements(requirements)
          requirements.each do |dep|
            next unless dep["requirement"]

            Python::Requirement.new(dep["requirement"].split(","))
          rescue Gem::Requirement::BadRequirementError => e
            raise Dependabot::DependencyFileNotEvaluatable, e.message
          end
        end

        def write_temporary_dependency_files
          dependency_files.
            reject { |f| f.name == ".python-version" }.
            each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, file.content)
            end
        end

        # Write a setup.py with only entries for the requires fields.
        #
        # This sanitization is far from perfect (it will fail if any of the
        # entries are dynamic), but it is an alternative approach to the one
        # used in parser.py which sometimes succeeds when that has failed.
        def write_sanitized_setup_file
          install_requires = get_regexed_req_array(INSTALL_REQUIRES_REGEX)
          setup_requires = get_regexed_req_array(SETUP_REQUIRES_REGEX)
          tests_require = get_regexed_req_array(TESTS_REQUIRE_REGEX)
          extras_require = get_regexed_req_dict(EXTRAS_REQUIRE_REGEX)

          tmp = "from setuptools import setup\n\n"\
                "setup(name=\"sanitized-package\",version=\"0.0.1\","

          tmp += "install_requires=#{install_requires}," if install_requires
          tmp += "setup_requires=#{setup_requires}," if setup_requires
          tmp += "tests_require=#{tests_require}," if tests_require
          tmp += "extras_require=#{extras_require}," if extras_require
          tmp += ")"

          File.write("setup.py", tmp)
        end

        def get_regexed_req_array(regex)
          return unless (mch = setup_file.content.match(regex))

          "[#{mch.post_match[0..closing_bracket_index(mch.post_match, '[')]}"
        end

        def get_regexed_req_dict(regex)
          return unless (mch = setup_file.content.match(regex))

          "{#{mch.post_match[0..closing_bracket_index(mch.post_match, '{')]}"
        end

        def closing_bracket_index(string, bracket)
          closes_required = 1

          string.chars.each_with_index do |char, index|
            closes_required += 1 if char == bracket
            closes_required -= 1 if char == CLOSING_BRACKET.fetch(bracket)
            return index if closes_required.zero?
          end

          0
        end

        def normalised_name(name, extras)
          NameNormaliser.normalise_including_extras(name, extras)
        end

        def setup_file
          dependency_files.find { |f| f.name == "setup.py" }
        end
      end
    end
  end
end
