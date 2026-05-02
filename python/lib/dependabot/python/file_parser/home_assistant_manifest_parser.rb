# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/python/name_normaliser"
require "dependabot/python/requirement_parser"
require "dependabot/python/requirement"

module Dependabot
  module Python
    class FileParser
      class HomeAssistantManifestParser
        extend T::Sig

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          manifest_files.each do |file|
            requirements = parsed_manifest(file).fetch("requirements", [])
            raise Dependabot::DependencyFileNotEvaluatable, file.path unless requirements.is_a?(Array)

            # Home Assistant treats these entries as pip requirement strings, so each valid
            # string becomes a normal Dependabot pip dependency.
            requirements.each do |requirement_string|
              next unless requirement_string.is_a?(String)

              dependency_set << parse_requirement(requirement_string, file)
            end
          end

          dependency_set
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def manifest_files
          dependency_files.select { |file| file.name.match?(Dependabot::Python::FileParser::HOME_ASSISTANT_MANIFEST_PATTERN) }
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Hash[String, T.untyped]) }
        def parsed_manifest(file)
          JSON.parse(T.must(file.content))
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        sig do
          params(
            requirement_string: String,
            file: Dependabot::DependencyFile
          ).returns(Dependabot::Dependency)
        end
        def parse_requirement(requirement_string, file)
          parsed = Dependabot::Python::RequirementParser.parse(requirement_string)
          raise Dependabot::DependencyFileNotEvaluatable, file.path unless parsed

          extras = Array(parsed[:extras])
          Dependency.new(
            name: normalised_name(parsed[:name], extras),
            version: parsed[:version],
            requirements: [{
              requirement: parsed[:requirement],
              file: file.name,
              groups: [],
              source: nil
            }],
            package_manager: "pip",
            metadata: extras_metadata(extras)
          )
        rescue Gem::Requirement::BadRequirementError
          raise Dependabot::DependencyFileNotEvaluatable, file.path
        end

        sig { params(name: String, extras: T::Array[String]).returns(String) }
        def normalised_name(name, extras)
          NameNormaliser.normalise_including_extras(name, extras)
        end

        sig { params(extras: T::Array[String]).returns(T::Hash[Symbol, String]) }
        def extras_metadata(extras)
          return {} if extras.empty?

          { extras: extras.join(",") }
        end
      end
    end
  end
end
