# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/swift/file_updater"
require "dependabot/swift/url_helpers"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Updates version requirements in project.pbxproj files for
      # XCRemoteSwiftPackageReference entries that match the dependencies
      # being updated. This ensures the Xcode project stays consistent
      # with the updated Package.resolved.
      class PbxprojUpdater
        extend T::Sig

        PACKAGE_REF_BLOCK = T.let(
          /
            (isa\s*=\s*XCRemoteSwiftPackageReference;\s*
            repositoryURL\s*=\s*")
            ([^"]+)
            (";\s*
            requirement\s*=\s*\{)
            ([^}]*)
            (\};)
          /mx,
          Regexp
        )

        KIND_PATTERN = T.let(/kind\s*=\s*(\w+);/, Regexp)
        MIN_VERSION_PATTERN = T.let(/minimumVersion\s*=\s*[0-9A-Za-z.+-]+;/, Regexp)
        VERSION_PATTERN = T.let(/\bversion\s*=\s*[0-9A-Za-z.+-]+;/, Regexp)

        sig do
          params(
            pbxproj_file: Dependabot::DependencyFile,
            dependencies: T::Array[Dependabot::Dependency]
          ).void
        end
        def initialize(pbxproj_file:, dependencies:)
          @pbxproj_file = pbxproj_file
          @dependencies = dependencies
        end

        sig { returns(String) }
        def updated_pbxproj_content
          content = pbxproj_file.content
          unless content
            raise Dependabot::DependencyFileNotParseable.new(
              pbxproj_file.name,
              "#{pbxproj_file.name} has no content"
            )
          end

          dep_lookup = build_dependency_lookup

          content.gsub(PACKAGE_REF_BLOCK) do
            prefix = T.must(Regexp.last_match(1))
            url = T.must(Regexp.last_match(2))
            mid = T.must(Regexp.last_match(3))
            req_block = T.must(Regexp.last_match(4))
            suffix = T.must(Regexp.last_match(5))

            normalized = normalize_url(url)
            dep = dep_lookup[normalized]

            if dep&.version
              updated_block = update_requirement_block(req_block, T.must(dep.version))
              "#{prefix}#{url}#{mid}#{updated_block}#{suffix}"
            else
              T.must(Regexp.last_match(0))
            end
          end
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :pbxproj_file

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Hash[String, Dependabot::Dependency]) }
        def build_dependency_lookup
          dependencies.to_h { |dep| [dep.name, dep] }
        end

        sig { params(url: String).returns(String) }
        def normalize_url(url)
          UrlHelpers.normalize_name(SharedHelpers.scp_to_standard(url))
        end

        sig { params(req_block: String, target_version: String).returns(String) }
        def update_requirement_block(req_block, target_version)
          kind = req_block.match(KIND_PATTERN)&.captures&.first

          case kind
          when "upToNextMajorVersion", "upToNextMinorVersion", "versionRange"
            req_block.sub(MIN_VERSION_PATTERN, "minimumVersion = #{target_version};")
          when "exactVersion"
            if req_block.match?(VERSION_PATTERN)
              req_block.sub(VERSION_PATTERN, "version = #{target_version};")
            else
              req_block.sub(MIN_VERSION_PATTERN, "minimumVersion = #{target_version};")
            end
          else
            # branch, revision, or unknown — no version update needed
            req_block
          end
        end
      end
    end
  end
end
