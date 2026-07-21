# typed: strict
# frozen_string_literal: true

require "dependabot/bun/file_updater/package_json_updater"

module Dependabot
  module Bun
    class FileUpdater < Dependabot::FileUpdaters::Base
      class PackageJsonUpdater
        module RequirementHelpers
          extend T::Sig

          class RequirementDeclaration < T::Struct
            const :requirement, T.nilable(String)
          end

          RequirementLike = T.type_alias do
            T.any(Dependabot::DependencyRequirement, RequirementDeclaration)
          end

          private

          sig do
            params(
              dependency_name: String,
              dependency_req: T.nilable(RequirementLike),
              content: String
            ).returns(String)
          end
          def declaration_line(dependency_name:, dependency_req:, content:)
            git_dependency = source_string(dependency_req, :type) == "git"

            unless git_dependency
              requirement = requirement_string(dependency_req)
              return "" unless requirement

              return content.match(
                /"#{Regexp.escape(dependency_name)}"\s*:\s*
                                                  "#{Regexp.escape(requirement)}"/x
              ).to_s
            end

            source_url = source_string(dependency_req, :url)
            return "" unless source_url

            username, repo = source_url.split("/").last(2)
            return "" unless username && repo

            content.match(
              %r{"#{Regexp.escape(dependency_name)}"\s*:\s*
                 ".*?#{Regexp.escape(username)}/#{Regexp.escape(repo)}.*"}x
            ).to_s
          end

          sig do
            params(
              original_line: String,
              old_req: T.nilable(RequirementLike),
              new_req: RequirementLike
            ).returns(String)
          end
          def replacement_declaration_line(original_line:, old_req:, new_req:)
            was_git_dependency = source_string(old_req, :type) == "git"
            now_git_dependency = source_string(new_req, :type) == "git"
            old_requirement = requirement_string(old_req)
            new_requirement = requirement_string(new_req)

            unless was_git_dependency
              return original_line unless old_requirement && new_requirement

              return original_line.gsub(
                %("#{old_requirement}"),
                %("#{new_requirement}")
              )
            end

            unless now_git_dependency
              return original_line unless new_requirement

              return original_line.gsub(
                /(?<=\s").*[^\\](?=")/,
                new_requirement
              )
            end

            if original_line.match?(/#[\^~=<>]|semver:/)
              return original_line unless new_requirement

              return update_git_semver_requirement(
                original_line: original_line,
                old_requirement: old_requirement,
                new_requirement: new_requirement
              )
            end

            original_line.gsub(
              %(##{source_string(old_req, :ref)}"),
              %(##{source_string(new_req, :ref)}")
            )
          end

          sig do
            params(
              original_line: String,
              old_requirement: T.nilable(String),
              new_requirement: String
            ).returns(String)
          end
          def update_git_semver_requirement(original_line:, old_requirement:, new_requirement:)
            if original_line.include?("semver:")
              return original_line.gsub(
                %(semver:#{old_requirement}),
                %(semver:#{new_requirement})
              )
            end

            Kernel.raise "Not a semver req!" unless original_line.match?(/#[\^~=<>]/)

            original_line.gsub(
              %(##{old_requirement}),
              %(##{new_requirement})
            )
          end

          sig { params(requirement: T.nilable(RequirementLike)).returns(T.nilable(String)) }
          def requirement_string(requirement)
            requirement&.requirement
          end

          sig { params(requirement: T.nilable(String)).returns(RequirementDeclaration) }
          def requirement_declaration(requirement)
            RequirementDeclaration.new(requirement: requirement)
          end

          sig do
            params(
              requirement: T.nilable(RequirementLike),
              key: Dependabot::DependencyRequirement::Key
            ).returns(T.nilable(String))
          end
          def source_string(requirement, key)
            return unless requirement.is_a?(Dependabot::DependencyRequirement)

            value = requirement.source&.[](key)
            value if value.is_a?(String)
          end
        end
      end
    end
  end
end
