# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/shared_helpers"
require "dependabot/python/file_parser"
require "dependabot/python/native_helpers"
require "dependabot/python/name_normaliser"
require "sorbet-runtime"

module Dependabot
  module Python
    class FileParser < Dependabot::FileParsers::Base
      class SetupFileParser
        extend T::Sig

        class SetupDependency < T::ImmutableStruct
          const :name, String
          const :version, T.nilable(String)
          const :markers, T.nilable(String)
          const :file, String
          const :requirement, T.nilable(String)
          const :requirement_type, String
          const :extras, T::Array[String]
        end
        private_constant :SetupDependency

        INSTALL_REQUIRES_REGEX = /install_requires\s*=\s*\[/m
        SETUP_REQUIRES_REGEX = /setup_requires\s*=\s*\[/m
        TESTS_REQUIRE_REGEX = /tests_require\s*=\s*\[/m
        EXTRAS_REQUIRE_REGEX = /extras_require\s*=\s*\{/m

        CLOSING_BRACKET = T.let({ "[" => "]", "{" => "}" }.freeze, T::Hash[String, String])

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependency_set
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          parsed_setup_file.each do |dep|
            # If a requirement has a `<` or `<=` marker then updating it is
            # probably blocked. Ignore it.
            next if dep.markers&.include?("<")

            # If the requirement is our inserted version, ignore it
            # (we wouldn't be able to update it)
            next if dep.version == "0.0.1+dependabot"

            dependencies <<
              Dependency.new(
                name: normalise(dep.name),
                version: dep.version&.include?("*") ? nil : dep.version,
                requirements: [{
                  requirement: dep.requirement,
                  file: Pathname.new(dep.file).cleanpath.to_path,
                  source: nil,
                  groups: [dep.requirement_type]
                }],
                package_manager: "pip",
                metadata: extras_metadata(dep.extras)
              )
          end
          dependencies
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[SetupDependency]) }
        def parsed_setup_file
          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files
            run_setup_helper
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise Dependabot::DependencyFileNotEvaluatable, e.message if e.message.start_with?("InstallationError")

          file = setup_file
          return [] unless file

          parsed_sanitized_setup_file(file)
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Array[SetupDependency]) }
        def parsed_sanitized_setup_file(file)
          SharedHelpers.in_a_temporary_directory do
            write_sanitized_setup_file(T.must(file.content))
            run_setup_helper
          end
        rescue SharedHelpers::HelperSubprocessFailed
          # Assume there are no dependencies in setup.py files that fail to
          # parse. This isn't ideal, and we should continue to improve
          # parsing, but there are a *lot* of things that can go wrong at
          # the moment!
          []
        end

        sig { returns(T::Array[SetupDependency]) }
        def run_setup_helper
          result = SharedHelpers.run_helper_subprocess(
            command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
            function: "parse_setup",
            args: [Dir.pwd]
          )
          parse_setup_result(result)
        end

        sig { params(result: Object).returns(T::Array[SetupDependency]) }
        def parse_setup_result(result)
          PyprojectValueParser.array(result, "parse_setup result").each_with_index.map do |value, index|
            context = "parse_setup result[#{index}]"
            fields = PyprojectValueParser.object_hash(value, context)
            requirement = PyprojectValueParser.optional_string(fields["requirement"], "#{context}.requirement")
            Python::Requirement.new(requirement.split(",")) unless requirement.nil?

            SetupDependency.new(
              name: PyprojectValueParser.string(fields["name"], "#{context}.name"),
              version: PyprojectValueParser.optional_string(fields["version"], "#{context}.version"),
              markers: PyprojectValueParser.optional_string(fields["markers"], "#{context}.markers"),
              file: PyprojectValueParser.string(fields["file"], "#{context}.file"),
              requirement: requirement,
              requirement_type: PyprojectValueParser.string(fields["requirement_type"], "#{context}.requirement_type"),
              extras: PyprojectValueParser.string_array(fields["extras"], "#{context}.extras")
            )
          end
        rescue TypeError, Gem::Requirement::BadRequirementError => e
          raise Dependabot::DependencyFileNotEvaluatable, e.message
        end

        sig { void }
        def write_temporary_dependency_files
          dependency_files
            .reject { |f| f.name == ".python-version" }
            .each do |file|
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
        sig { params(content: String).void }
        def write_sanitized_setup_file(content)
          install_requires = get_regexed_req_array(content, INSTALL_REQUIRES_REGEX)
          setup_requires = get_regexed_req_array(content, SETUP_REQUIRES_REGEX)
          tests_require = get_regexed_req_array(content, TESTS_REQUIRE_REGEX)
          extras_require = get_regexed_req_dict(content, EXTRAS_REQUIRE_REGEX)

          tmp = "from setuptools import setup\n\n" \
                "setup(name=\"sanitized-package\",version=\"0.0.1\","

          tmp += "install_requires=#{install_requires}," if install_requires
          tmp += "setup_requires=#{setup_requires}," if setup_requires
          tmp += "tests_require=#{tests_require}," if tests_require
          tmp += "extras_require=#{extras_require}," if extras_require
          tmp += ")"

          File.write("setup.py", tmp)
        end

        sig { params(content: String, regex: Regexp).returns(T.nilable(String)) }
        def get_regexed_req_array(content, regex)
          return unless (mch = content.match(regex))

          "[#{mch.post_match[0..closing_bracket_index(mch.post_match, '[')]}"
        end

        sig { params(content: String, regex: Regexp).returns(T.nilable(String)) }
        def get_regexed_req_dict(content, regex)
          return unless (mch = content.match(regex))

          "{#{mch.post_match[0..closing_bracket_index(mch.post_match, '{')]}"
        end

        sig { params(string: String, bracket: String).returns(Integer) }
        def closing_bracket_index(string, bracket)
          closes_required = 1

          string.chars.each_with_index do |char, index|
            closes_required += 1 if char == bracket
            closes_required -= 1 if char == CLOSING_BRACKET.fetch(bracket)
            return index if closes_required.zero?
          end

          0
        end

        sig { params(name: String, extras: T::Array[String]).returns(String) }
        def normalised_name(name, extras)
          NameNormaliser.normalise_including_extras(name, extras)
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
        end

        sig { params(extras: T::Array[String]).returns(T::Hash[Symbol, String]) }
        def extras_metadata(extras)
          return {} if extras.empty?

          { extras: extras.join(",") }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def setup_file
          dependency_files.find { |f| f.name == "setup.py" }
        end
      end
    end
  end
end
