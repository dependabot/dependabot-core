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

          T.must(
            workspace_deps.reduce(manifest.content.dup) do |content, dep|
              update_workspace_dependency(T.must(content), dep)
            end
          )
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

          # First try to update in the inline [workspace.dependencies] section
          workspace_section_regex = /\[workspace\.dependencies\](.*?)(?=\n\[|\n*\z)/m

          updated_content = content.gsub(workspace_section_regex) do |section|
            update_version_in_section(section, dep.name, old_req, new_req)
          end

          # If content didn't change, try table header notation [workspace.dependencies.name]
          if updated_content == content
            updated_content = update_table_header_notation(content, dep.name, old_req, new_req)
          end

          updated_content
        end

        sig { params(requirements: T.nilable(T::Array[T::Hash[Symbol, T.untyped]])).returns(T.nilable(String)) }
        def find_workspace_requirement(requirements)
          requirements&.find { |r| r[:groups]&.include?("workspace.dependencies") }
                      &.fetch(:requirement)
        end

        sig { params(section: String, dep_name: String, old_req: String, new_req: String).returns(String) }
        def update_version_in_section(section, dep_name, old_req, new_req)
          # Try double-quoted version first
          updated = section.gsub(
            /^(\s*#{Regexp.escape(dep_name)}\s*=\s*)"#{Regexp.escape(old_req)}"/m,
            "\\1\"#{new_req}\""
          )
          return updated if updated != section

          # Try single-quoted version
          updated = section.gsub(
            /^(\s*#{Regexp.escape(dep_name)}\s*=\s*)'#{Regexp.escape(old_req)}'/m,
            "\\1'#{new_req}'"
          )
          return updated if updated != section

          # Try unquoted version
          updated = section.gsub(
            /^(\s*#{Regexp.escape(dep_name)}\s*=\s*)#{Regexp.escape(old_req)}(\s|$)/m,
            "\\1#{new_req}\\2"
          )
          return updated if updated != section

          # Try inline table format with double quotes
          updated = section.gsub(
            /^(\s*#{Regexp.escape(dep_name)}\s*=\s*\{[^}]*version\s*=\s*)"#{Regexp.escape(old_req)}"/m,
            "\\1\"#{new_req}\""
          )
          return updated if updated != section

          # Try inline table format with single quotes
          section.gsub(
            /^(\s*#{Regexp.escape(dep_name)}\s*=\s*\{[^}]*version\s*=\s*)'#{Regexp.escape(old_req)}'/m,
            "\\1'#{new_req}'"
          )
        end

        sig { params(content: String, dep_name: String, old_req: String, new_req: String).returns(String) }
        def update_table_header_notation(content, dep_name, old_req, new_req)
          # Match [workspace.dependencies.name] section and its content until next section
          table_header_regex = /\[workspace\.dependencies\.#{Regexp.escape(dep_name)}\](.*?)(?=\n\[|\n*\z)/m

          content.gsub(table_header_regex) do |section|
            # Update version = "..." line within this section (double quotes)
            updated = section.gsub(
              /^(\s*version\s*=\s*)"#{Regexp.escape(old_req)}"/m,
              "\\1\"#{new_req}\""
            )

            # Try single quotes if double quotes didn't match
            if updated == section
              updated = section.gsub(
                /^(\s*version\s*=\s*)'#{Regexp.escape(old_req)}'/m,
                "\\1'#{new_req}'"
              )
            end

            # Also try unquoted version
            if updated == section
              updated = section.gsub(
                /^(\s*version\s*=\s*)#{Regexp.escape(old_req)}(\s|$)/m,
                "\\1#{new_req}\\2"
              )
            end

            updated
          end
        end
      end
    end
  end
end
