# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"
require "dependabot/python/requirement_parser"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileUpdater
      class HomeAssistantManifestUpdater
        extend T::Sig

        HOME_ASSISTANT_MANIFEST_PATTERN = T.let(
          %r{\A(?:custom_components|homeassistant/components)/[^/]+/manifest\.json\z},
          Regexp
        )

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = T.let(dependencies, T::Array[Dependabot::Dependency])
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_dependency_files
          updated_files = dependency_files.filter_map do |file|
            next unless file.name.match?(HOME_ASSISTANT_MANIFEST_PATTERN)

            updated_content = updated_manifest_content(file)
            next if updated_content == T.must(file.content)

            file.dup.tap { |f| f.content = updated_content }
          end

          raise "No files changed!" if updated_files.none?

          updated_files
        end

        private

        sig { returns(Dependabot::Dependency) }
        def dependency
          T.must(dependencies.first)
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def updated_manifest_content(file)
          manifest = JSON.parse(T.must(file.content))
          updated_requirements = manifest.fetch("requirements", [])
          raise Dependabot::DependencyFileNotEvaluatable, file.path unless updated_requirements.is_a?(Array)

          updated_requirements = updated_requirements.dup

          # Match both the file and the previous requirement so we only rewrite the exact
          # pin Dependabot is updating, not another requirement for the same package.
          dependency.requirements.zip(T.must(dependency.previous_requirements)).each do |new_req, old_req|
            next unless new_req[:file] == file.name

            updated_requirements.map! do |requirement|
              next requirement unless requirement.is_a?(String)

              parsed = Dependabot::Python::RequirementParser.parse(requirement)
              next requirement unless parsed
              next requirement unless matches_requirement?(parsed, old_req)

              requirement.sub(parsed[:requirement], T.must(new_req.fetch(:requirement)))
            end
          end

          manifest["requirements"] = updated_requirements
          JSON.pretty_generate(manifest)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        sig do
          params(
            parsed_requirement: T::Hash[Symbol, T.untyped],
            old_requirement: T.nilable(T::Hash[Symbol, T.untyped])
          ).returns(T::Boolean)
        end
        def matches_requirement?(parsed_requirement, old_requirement)
          requirement_name = normalised_name(parsed_requirement[:name], Array(parsed_requirement[:extras]))
          return false unless requirement_name == dependency.name

          return true unless old_requirement && old_requirement[:requirement]

          parsed_requirement[:requirement] == old_requirement[:requirement]
        end

        sig { params(name: String, extras: T::Array[String]).returns(String) }
        def normalised_name(name, extras)
          NameNormaliser.normalise_including_extras(name, extras)
        end
      end
    end
  end
end
