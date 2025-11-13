# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bazel/file_updater"

module Dependabot
  module Bazel
    class FileUpdater < Dependabot::FileUpdaters::Base
      module ExtensionDependencyUpdater
        extend T::Sig

        sig do
          params(
            content: String,
            dependency: Dependabot::Dependency
          ).returns(String)
        end
        def update_extension_dependency(content, dependency)
          req = dependency.requirements.first
          return content unless req

          source = req[:source]
          return content unless source.is_a?(Hash)

          metadata = req[:metadata]
          return content unless metadata.is_a?(Hash)

          line = metadata[:line]
          return content unless line.is_a?(Integer)

          ecosystem_type = source[:type]
          return content unless ecosystem_type.is_a?(String)

          previous_source = T.must(dependency.previous_requirements).first&.dig(:source) || {}

          case ecosystem_type
          when "go_modules"
            update_go_module_version(content, dependency, line)
          when "maven"
            update_maven_version(content, dependency, line, source, previous_source)
          when "cargo"
            update_cargo_version(content, dependency, line)
          else
            content
          end
        end

        private

        sig do
          params(
            content: String,
            dependency: Dependabot::Dependency,
            _line: Integer
          ).returns(String)
        end
        def update_go_module_version(content, dependency, _line)
          new_version = dependency.version
          return content unless new_version

          escaped_path = Regexp.escape(dependency.name)

          pattern = /(go_deps\.module\s*\([^)]*path\s*=\s*["']#{escaped_path}["'][^)]*)\)/m

          content.gsub(pattern) do |match|
            match.gsub(
              /version\s*=\s*["'][^"']*["']/,
              "version = \"#{new_version}\""
            )
          end
        end

        sig do
          params(
            content: String,
            dependency: Dependabot::Dependency,
            _line: Integer,
            source: T::Hash[Symbol, T.untyped],
            previous_source: T::Hash[Symbol, T.untyped]
          ).returns(String)
        end
        def update_maven_version(content, dependency, _line, source, previous_source)
          new_version = dependency.version
          return content unless new_version

          if source[:coordinate_string].is_a?(String)
            old_coordinate = previous_source[:coordinate_string]
            return content unless old_coordinate.is_a?(String)

            parts = old_coordinate.split(":")
            return content unless parts.length >= 3

            old_version = parts[2]
            return content unless old_version

            new_coordinate = old_coordinate.sub(old_version, new_version)

            quoted_old = Regexp.escape("\"#{old_coordinate}\"")
            quoted_new = "\"#{new_coordinate}\""
            content.gsub(/(\[\s*|,\s*)#{quoted_old}(\s*(?:,|\]))/, "\\1#{quoted_new}\\2")
          else
            group = source[:group]
            artifact = source[:artifact]
            return content unless group.is_a?(String) && artifact.is_a?(String)

            escaped_group = Regexp.escape(group)
            escaped_artifact = Regexp.escape(artifact)

            pattern = /(maven\.artifact\s*\([^)]*group\s*=\s*["']#{escaped_group}["']
                       [^)]*artifact\s*=\s*["']#{escaped_artifact}["'][^)]*)\)/mx

            content.gsub(pattern) do |match|
              match.gsub(
                /version\s*=\s*["'][^"']*["']/,
                "version = \"#{new_version}\""
              )
            end
          end
        end

        sig do
          params(
            content: String,
            dependency: Dependabot::Dependency,
            _line: Integer
          ).returns(String)
        end
        def update_cargo_version(content, dependency, _line)
          new_version = dependency.version
          return content unless new_version

          escaped_package = Regexp.escape(dependency.name)

          pattern = /(crate\.spec\s*\([^)]*package\s*=\s*["']#{escaped_package}["'][^)]*)\)/m

          content.gsub(pattern) do |match|
            match.gsub(
              /version\s*=\s*["']([=^~]?)([^"']*)["']/
            ) do
              operator = Regexp.last_match(1)
              "version = \"#{operator}#{new_version}\""
            end
          end
        end
      end
    end
  end
end
