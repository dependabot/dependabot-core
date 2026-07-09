# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/shared_helpers"
require "dependabot/dependency"
require "dependabot/shared/shared_file_updater"
require "fileutils"
require "tmpdir"

module Dependabot
  module Helm
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      class ChartUpdater
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency
          ).void
        end
        def initialize(dependency:)
          @dependency = dependency
        end

        sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def updated_chart_yaml_content(file)
          content = file.content
          yaml_obj = YAML.safe_load(T.must(content))

          content = update_chart_dependencies(T.must(content), yaml_obj, file)

          raise "Expected content to change!" if content == file.content

          content
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig do
          params(
            content: String,
            yaml_obj: T::Hash[String, Object],
            file: Dependabot::DependencyFile
          ).returns(String)
        end
        def update_chart_dependencies(content, yaml_obj, file)
          if update_chart_dependency?(file) && yaml_obj["dependencies"]
            T.cast(yaml_obj["dependencies"], T::Array[T::Hash[String, Object]]).each do |dep|
              next unless dep["name"] == dependency.name

              old_version = dep["version"].to_s
              new_version = yaml_safe_value(updated_requirement_string(file, old_version) || dependency.version.to_s)

              pattern = /
              (\s+-\s+name:\s+#{Regexp.escape(dependency.name)}.*?\n\s+)
              (version:\s+)
              ["']?#{Regexp.escape(old_version)}["']?
            /mx
              content = content.gsub(pattern) do |match|
                match.gsub(/version: ["']?#{Regexp.escape(old_version)}["']?/, "version: #{new_version}")
              end
            end
          end
          content
        end

        # Wrap a requirement in double quotes when it would otherwise be
        # ambiguous as a YAML plain scalar: any whitespace, or a leading
        # YAML-indicator character (">", "<", "~", "|", etc.). Simple values
        # (exact, caret) are left bare, preserving the previous output.
        sig { params(value: String).returns(String) }
        def yaml_safe_value(value)
          return "\"#{value}\"" if value.match?(/\s/) || value.match?(/\A[>~<|&*!%@?:#,\[\]{}]/)

          value
        end

        # The strategy-updated requirement string for a specific chart entry,
        # matched by the entry's authored version (source[:tag]) so repeated
        # occurrences of the same chart name each get their own update. Falls
        # back to the first requirement for the file, then to nil (exact pin).
        sig { params(file: Dependabot::DependencyFile, old_version: String).returns(T.nilable(String)) }
        def updated_requirement_string(file, old_version)
          reqs = dependency.requirements.select do |r|
            r[:file] == file.name && r.dig(:metadata, :type) == :helm_chart
          end
          req = reqs.find { |r| r.dig(:source, :tag) == old_version } || reqs.first
          req && req[:requirement]
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def update_chart_dependency?(file)
          reqs = dependency.requirements.select { |r| r[:file] == file.name }
          reqs.any? { |r| r[:metadata]&.dig(:type) == :helm_chart }
        end
      end
    end
  end
end
