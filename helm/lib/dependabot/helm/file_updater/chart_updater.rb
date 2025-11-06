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
            yaml_obj: T::Hash[T.untyped, T.untyped],
            file: Dependabot::DependencyFile
          ).returns(String)
        end
        def update_chart_dependencies(content, yaml_obj, file)
          if update_chart_dependency?(file) && yaml_obj["dependencies"]
            yaml_obj["dependencies"].each do |dep|
              next unless dep["name"] == dependency.name

              old_version = dep["version"].to_s
              new_version = dependency.version

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

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def update_chart_dependency?(file)
          reqs = dependency.requirements.select { |r| r[:file] == file.name }
          reqs.any? { |r| r[:metadata]&.dig(:type) == :helm_chart }
        end
      end
    end
  end
end
