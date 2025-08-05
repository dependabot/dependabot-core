# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/cargo/file_updater"

module Dependabot
  module Cargo
    class FileUpdater
      class WorkspaceManifestUpdater
        extend T::Sig

        sig { params(dependencies: T::Array[Dependabot::Dependency], manifest: Dependabot::DependencyFile).void }
        def initialize(dependencies:, manifest:)
          @dependencies = T.let(dependencies, T::Array[Dependabot::Dependency])
          @manifest = T.let(manifest, Dependabot::DependencyFile)
        end

        sig { returns(String) }
        def updated_manifest_content
          workspace_deps = dependencies.select { |dep| workspace_dependency?(dep) }

          return T.must(manifest.content) if workspace_deps.empty?

          T.must(workspace_deps.reduce(manifest.content.dup) do |content, dep|
            updated_content = update_workspace_dependency(T.must(content), dep)

            raise "Expected content to change!" if content == updated_content

            updated_content
          end)
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { params(dep: Dependabot::Dependency).returns(T::Boolean) }
        def workspace_dependency?(dep)
          dep.requirements.any? { |r| r[:groups]&.include?("workspace.dependencies") }
        end

        sig { params(content: String, dep: Dependabot::Dependency).returns(String) }
        def update_workspace_dependency(content, dep)
          old_req = find_workspace_requirement(dep.previous_requirements)
          new_req = find_workspace_requirement(dep.requirements)

          return content if old_req == new_req || !old_req || !new_req

          # Update version in [workspace.dependencies] section
          workspace_section_regex = /\[workspace\.dependencies\](.*?)(?=\n\[|\n*\z)/m

          content.gsub(workspace_section_regex) do |section|
            update_version_in_section(section, dep.name, old_req, new_req)
          end
        end

        sig { params(requirements: T.nilable(T::Array[T::Hash[Symbol, T.untyped]])).returns(T.nilable(String)) }
        def find_workspace_requirement(requirements)
          requirements&.find { |r| r[:groups]&.include?("workspace.dependencies") }
                      &.fetch(:requirement)
        end

        sig { params(section: String, dep_name: String, old_req: String, new_req: String).returns(String) }
        def update_version_in_section(section, dep_name, old_req, new_req)
          # Try quoted version first
          updated = section.gsub(
            /^(\s*#{Regexp.escape(dep_name)}\s*=\s*)"#{Regexp.escape(old_req)}"/m,
            "\\1\"#{new_req}\""
          )
          return updated if updated != section

          # Try unquoted version
          updated = section.gsub(
            /^(\s*#{Regexp.escape(dep_name)}\s*=\s*)#{Regexp.escape(old_req)}(\s|$)/m,
            "\\1#{new_req}\\2"
          )
          return updated if updated != section

          # Try inline table format
          section.gsub(
            /^(\s*#{Regexp.escape(dep_name)}\s*=\s*\{[^}]*version\s*=\s*)"#{Regexp.escape(old_req)}"/m,
            "\\1\"#{new_req}\""
          )
        end
      end
    end
  end
end
