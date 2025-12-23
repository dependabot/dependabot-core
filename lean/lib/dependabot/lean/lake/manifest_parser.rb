# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/lean"

module Dependabot
  module Lean
    module Lake
      class ManifestParser
        extend T::Sig

        sig { params(manifest_file: Dependabot::DependencyFile).void }
        def initialize(manifest_file:)
          @manifest_file = manifest_file
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def parse
          manifest = parse_manifest
          packages = manifest.fetch("packages", [])

          packages.filter_map do |package|
            parse_package(package)
          end
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest_file

        sig { returns(T::Hash[String, T.untyped]) }
        def parse_manifest
          JSON.parse(T.must(manifest_file.content))
        rescue JSON::ParserError => e
          raise Dependabot::DependencyFileNotParseable.new(
            manifest_file.path,
            e.message
          )
        end

        sig { params(package: T::Hash[String, T.untyped]).returns(T.nilable(Dependabot::Dependency)) }
        def parse_package(package)
          # Only support git-based packages for now
          return unless package["type"] == "git"

          name = package["name"]
          return unless name

          url = package["url"]
          rev = package["rev"]
          input_rev = package["inputRev"]

          return unless url && rev

          Dependabot::Dependency.new(
            name: name,
            version: rev,
            requirements: [{
              requirement: nil,
              file: LAKE_MANIFEST_FILENAME,
              groups: [],
              source: {
                type: "git",
                url: url,
                ref: input_rev,
                branch: input_rev
              }
            }],
            package_manager: PACKAGE_MANAGER
          )
        end
      end
    end
  end
end
