# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/lean"

module Dependabot
  module Lean
    module Lake
      class ManifestUpdater
        extend T::Sig

        sig do
          params(
            manifest_content: String,
            dependencies: T::Array[Dependabot::Dependency]
          ).void
        end
        def initialize(manifest_content:, dependencies:)
          @manifest_content = manifest_content
          @dependencies = dependencies
        end

        sig { returns(String) }
        def updated_manifest_content
          manifest = JSON.parse(manifest_content)
          packages = manifest.fetch("packages", [])

          dependencies.each do |dep|
            update_package_in_manifest(packages, dep)
          end

          # Preserve original JSON formatting style
          JSON.pretty_generate(manifest)
        end

        private

        sig { returns(String) }
        attr_reader :manifest_content

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig do
          params(
            packages: T::Array[T::Hash[String, T.untyped]],
            dependency: Dependabot::Dependency
          ).void
        end
        def update_package_in_manifest(packages, dependency)
          package = packages.find { |p| p["name"] == dependency.name }
          return unless package

          previous_version = dependency.previous_version
          new_version = dependency.version

          return unless previous_version && new_version
          return if previous_version == new_version

          # Update the rev (commit SHA)
          package["rev"] = new_version
        end
      end
    end
  end
end
