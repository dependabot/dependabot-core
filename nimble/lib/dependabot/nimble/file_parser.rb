# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/nimble/manifest"
require "dependabot/nimble/requirement"
require "dependabot/nimble/version"

module Dependabot
  module Nimble
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = {}

        manifests.each do |file|
          Manifest.new(file.content.to_s).dependencies.each do |entry|
            requirement = requirement_for(entry, file)
            (dependency_set[entry.name] ||= []) << requirement
          end
        end

        dependency_set.map { |name, requirements| dependency(name, requirements) }
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def manifests
        dependency_files.select { |file| file.name.end_with?(FileFetcher::MANIFEST_SUFFIX) }
      end

      sig do
        params(entry: Manifest::Requires, file: Dependabot::DependencyFile)
          .returns(Dependabot::DependencyRequirement)
      end
      def requirement_for(entry, file)
        Dependabot::DependencyRequirement.create(
          requirement: entry.requirement.empty? ? nil : entry.requirement,
          file: file.name,
          groups: [entry.task || "dependencies"],
          source: nil
        )
      end

      sig do
        params(name: String, requirements: T::Array[Dependabot::DependencyRequirement])
          .returns(Dependabot::Dependency)
      end
      def dependency(name, requirements)
        Dependabot::Dependency.new(
          name: name,
          version: version_for(requirements),
          requirements: requirements,
          package_manager: "nimble"
        )
      end

      # The version a requirement starts from, when every requirement of the package agrees
      # on one; otherwise the package has no single current version.
      sig { params(requirements: T::Array[Dependabot::DependencyRequirement]).returns(T.nilable(String)) }
      def version_for(requirements)
        versions = requirements.map { |requirement| Requirement.lower_bound(requirement.requirement_string) }
        return unless versions.uniq.length == 1

        version = versions.first
        version if version && Version.correct?(version)
      end

      sig { override.void }
      def check_required_files
        return if manifests.any?

        raise Dependabot::DependencyFileNotFound.new(nil, FileFetcher.required_files_message)
      end
    end
  end
end

Dependabot::FileParsers.register("nimble", Dependabot::Nimble::FileParser)
