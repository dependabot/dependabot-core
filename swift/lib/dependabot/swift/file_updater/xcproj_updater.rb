# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/file_updaters/base"
require "dependabot/swift/url_helpers"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Updates version requirements of remote Swift packages in project.xcproj,
      # the JSON project format that Xcode 27.2 and later use by default.
      #
      # The file is edited in place instead of being re-serialized: Xcode writes
      # it in a canonical layout (trailing commas, one-line objects) that a JSON
      # generator would not reproduce, so re-serializing would rewrite the whole
      # file. Only the version strings change.
      class XcprojUpdater
        extend T::Sig

        # An object nested at most one level deep. A package is one of these: its
        # only nested object is the version constraint, which holds strings only.
        # Properties are looked up inside the object, so their order does not
        # matter (Xcode writes "kind", "repository", "version", but other tools
        # and hand edits may not).
        PACKAGE_OBJECT = /\{(?:[^{}]|\{[^{}]*\})*\}/m
        REPOSITORY_VALUE = /"repository"\s*:\s*"(?<url>[^"]+)"/
        VERSION_OBJECT = /(?<open>"version"\s*:\s*\{)(?<constraint>[^}]*)(?<close>\})/m

        SINGLE_VERSION_KEYS = %w(version up-to-next-major-version up-to-next-minor-version version-range-min).freeze
        VERSION_RANGE_PATTERN = /("version-range"\s*:\s*")[^"]*?(\.\.<)/
        VERSION_RANGE_PAIR_PATTERN = /
            "version-range-min"\s*:\s*"(?<min>[^"]*)"\s*,\s*
            "version-range-max"\s*:\s*"(?<max>[^"]*)"
          /mx
        BASIC_VERSION_PATTERN = /\A[0-9.]+\z/

        sig do
          params(
            xcproj_file: Dependabot::DependencyFile,
            dependencies: T::Array[Dependabot::Dependency]
          ).void
        end
        def initialize(xcproj_file:, dependencies:)
          @xcproj_file = xcproj_file
          @dependencies = dependencies
        end

        sig { returns(String) }
        def updated_xcproj_content
          content = xcproj_file.content
          unless content
            raise Dependabot::DependencyFileNotParseable.new(
              xcproj_file.name,
              "#{xcproj_file.name} has no content"
            )
          end

          dep_lookup = dependencies.to_h { |dep| [dep.name, dep] }

          content.gsub(PACKAGE_OBJECT) do
            package = T.must(Regexp.last_match(0))
            url = package[REPOSITORY_VALUE, :url]
            version = url && dep_lookup[normalize_url(url)]&.version

            version ? update_package(package, version) : package
          end
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :xcproj_file

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { params(package: String, target_version: String).returns(String) }
        def update_package(package, target_version)
          package.sub(VERSION_OBJECT) do
            match = T.must(Regexp.last_match)
            "#{match[:open]}#{update_constraint(T.must(match[:constraint]), target_version)}#{match[:close]}"
          end
        end

        sig { params(url: String).returns(String) }
        def normalize_url(url)
          UrlHelpers.normalize_name(SharedHelpers.scp_to_standard(url))
        end

        # Same rules as PbxprojUpdater: exact versions are replaced, the lower
        # bound of every other version requirement is raised, and branch or
        # revision requirements are left alone.
        sig { params(constraint: String, target_version: String).returns(String) }
        def update_constraint(constraint, target_version)
          return constraint if constraint.match?(/"(?:branch|revision)"\s*:/)

          key = SINGLE_VERSION_KEYS.find { |k| constraint.match?(/"#{Regexp.escape(k)}"\s*:/) }

          if key == "version-range-min"
            update_version_range_pair(constraint, target_version)
          elsif key
            replace_value(constraint, key, target_version)
          else
            constraint.sub(VERSION_RANGE_PATTERN) { "#{Regexp.last_match(1)}#{target_version}#{Regexp.last_match(2)}" }
          end
        end

        # Xcode only uses the version-range-min / version-range-max pair when a
        # bound is not a plain dotted number, and writes "version-range":
        # "MIN..<MAX" otherwise. Keep that canonical form after the update.
        sig { params(constraint: String, target_version: String).returns(String) }
        def update_version_range_pair(constraint, target_version)
          constraint.sub(VERSION_RANGE_PAIR_PATTERN) do
            match = T.must(Regexp.last_match)
            max_version = T.must(match[:max])
            if basic_version?(target_version) && basic_version?(max_version)
              "\"version-range\": \"#{target_version}..<#{max_version}\""
            else
              replace_value(T.must(match[0]), "version-range-min", target_version)
            end
          end
        end

        sig { params(constraint: String, key: String, value: String).returns(String) }
        def replace_value(constraint, key, value)
          constraint.sub(/("#{Regexp.escape(key)}"\s*:\s*")[^"]*(")/) do
            "#{Regexp.last_match(1)}#{value}#{Regexp.last_match(2)}"
          end
        end

        sig { params(version: String).returns(T::Boolean) }
        def basic_version?(version)
          version.match?(BASIC_VERSION_PATTERN)
        end
      end
    end
  end
end
