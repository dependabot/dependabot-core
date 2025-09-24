# typed: strict
# frozen_string_literal: true

require "dependabot/python/file_updater"

module Dependabot
  module Python
    class FileUpdater
      class PipfileManifestUpdater
        extend T::Sig

        sig { params(dependencies: T::Array[Dependency], manifest: DependencyFile).void }
        def initialize(dependencies:, manifest:)
          @dependencies = dependencies
          @manifest = manifest
        end

        sig { returns(T.nilable(String)) }
        def updated_manifest_content
          dependencies
            .select { |dep| requirement_changed?(dep) }
            .reduce(manifest.content.dup) do |content, dep|
              updated_content = content

              updated_content = update_requirements(
                content: T.must(updated_content),
                dependency: dep
              )

              raise "Content did not change!" if content == updated_content

              updated_content
            end
        end

        private

        sig { returns(T::Array[Dependency]) }
        attr_reader :dependencies

        sig { returns(DependencyFile) }
        attr_reader :manifest

        sig { params(content: String, dependency: Dependency).returns(String) }
        def update_requirements(content:, dependency:)
          updated_content = content.dup

          # The UpdateChecker ensures the order of requirements is preserved
          # when updating, so we can zip them together in new/old pairs.
          reqs = dependency.requirements
                           .zip(T.must(dependency.previous_requirements))
                           .reject { |new_req, old_req| new_req == old_req }

          # Loop through each changed requirement
          reqs.each do |new_req, old_req|
            raise "Bad req match" unless new_req[:file] == T.must(old_req)[:file]
            next if new_req[:requirement] == T.must(old_req)[:requirement]
            next unless new_req[:file] == manifest.name

            updated_content = update_manifest_req(
              content: updated_content,
              dep: dependency,
              old_req: T.must(old_req).fetch(:requirement),
              new_req: new_req.fetch(:requirement)
            )
          end

          updated_content
        end

        sig do
          params(
            content: String,
            dep: Dependency,
            old_req: String,
            new_req: String
          ).returns(String)
        end
        def update_manifest_req(content:, dep:, old_req:, new_req:)
          simple_declaration = content.scan(declaration_regex(dep))
                                      .find { |m| m.include?(old_req) }

          if simple_declaration
            simple_declaration_regex =
              /(?:^|["'])#{Regexp.escape(simple_declaration.to_s)}/
            content.gsub(simple_declaration_regex) do |line|
              line.gsub(old_req, new_req)
            end
          elsif content.match?(table_declaration_version_regex(dep))
            content.gsub(table_declaration_version_regex(dep)) do |part|
              line = T.must(content.match(table_declaration_version_regex(dep)))
                      .named_captures.fetch("version_declaration")
              new_line = T.must(line).gsub(old_req, new_req)
              part.gsub(T.must(line), new_line)
            end
          else
            content
          end
        end

        sig { params(dep: Dependency).returns(Regexp) }
        def declaration_regex(dep)
          escaped_name = Regexp.escape(dep.name).gsub("\\-", "[-_.]")
          /(?:^|["'])#{escaped_name}["']?\s*=.*$/i
        end

        sig { params(dep: Dependabot::Dependency).returns(Regexp) }
        def table_declaration_version_regex(dep)
          /
            packages\.#{Regexp.quote(dep.name)}\]
            (?:(?!^\[).)+
            (?<version_declaration>version\s*=[^\[]*)$
          /mx
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def requirement_changed?(dependency)
          changed_requirements =
            dependency.requirements - T.must(dependency.previous_requirements)

          changed_requirements.any? { |f| f[:file] == manifest.name }
        end
      end
    end
  end
end
