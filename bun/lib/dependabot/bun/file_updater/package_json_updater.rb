# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/bun/file_updater"

module Dependabot
  module Bun
    class FileUpdater < Dependabot::FileUpdaters::Base
      class PackageJsonUpdater
        require_relative "package_json_updater/requirement_helpers"

        include RequirementHelpers
        extend T::Sig

        LOCAL_PACKAGE = T.let([/portal:/, /file:/].freeze, T::Array[Regexp])

        PATCH_PACKAGE = T.let([/patch:/].freeze, T::Array[Regexp])

        sig do
          params(
            package_json: Dependabot::DependencyFile,
            dependencies: T::Array[Dependabot::Dependency]
          ).void
        end
        def initialize(package_json:, dependencies:)
          @package_json = package_json
          @dependencies = dependencies
        end

        sig { returns(Dependabot::DependencyFile) }
        def updated_package_json
          updated_file = package_json.dup
          updated_file.content = updated_package_json_content
          updated_file
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :package_json

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T.nilable(String)) }
        def updated_package_json_content
          # checks if we are updating single dependency in package.json
          unique_deps_count = dependencies.map(&:name).to_a.uniq.compact.length

          dependencies.reduce(package_json.content.dup) do |content, dep|
            updated_requirements(dep)&.each do |new_req|
              old_req = old_requirement(dep, new_req)

              new_content = update_package_json_declaration(
                package_json_content: T.must(content),
                dependency_name: dep.name,
                old_req: old_req,
                new_req: new_req
              )

              # package.json does not always contain the same dependencies compared to the
              # "dependencies" list. For example, the dependencies object can contain same name dependency
              # "dep" => "1.0.0" and "dev" => "1.0.1" while package.json can only contain "dep" => "1.0.0".
              # The other dependency is not present in package.json so we don't have to update it — this is
              # most likely a transitive dependency which only needs an update in the lockfile. For a batch
              # with a single unique dependency name we tolerate this no-op update, but when multiple unique
              # dependencies are being updated and none change the content we treat that as unexpected and raise.
              raise "Expected content to change!" if content == new_content && unique_deps_count > 1

              content = new_content
            end

            new_requirements(dep).each do |new_req|
              old_req = old_requirement(dep, new_req)

              content = update_package_json_resolutions(
                package_json_content: T.must(content),
                new_req: new_req,
                dependency: dep,
                old_req: old_req
              )
            end

            content
          end
        end
        sig do
          params(
            dependency: Dependabot::Dependency,
            new_requirement: Dependabot::DependencyRequirement
          )
            .returns(T.nilable(Dependabot::DependencyRequirement))
        end
        def old_requirement(dependency, new_requirement)
          T.must(dependency.previous_requirements)
           .select { |r| r.file == package_json.name }
           .find { |r| r.groups == new_requirement.groups }
        end

        sig do
          params(dependency: Dependabot::Dependency)
            .returns(T::Array[Dependabot::DependencyRequirement])
        end
        def new_requirements(dependency)
          dependency.requirements.select { |r| r.file == package_json.name }
        end

        sig do
          params(dependency: Dependabot::Dependency)
            .returns(T.nilable(T::Array[Dependabot::DependencyRequirement]))
        end
        def updated_requirements(dependency)
          return unless dependency.previous_requirements

          preliminary_check_for_update(dependency)

          updated_requirement_pairs =
            dependency.requirements.zip(T.must(dependency.previous_requirements))
                      .reject do |new_req, old_req|
              next true if new_req == old_req
              next false unless old_req&.source.nil?

              new_req.requirement == old_req&.requirement
            end

          updated_requirement_pairs
            .map(&:first)
            .select { |r| r.file == package_json.name }
        end

        sig do
          params(
            package_json_content: String,
            new_req: Dependabot::DependencyRequirement,
            dependency_name: String,
            old_req: T.nilable(Dependabot::DependencyRequirement)
          )
            .returns(String)
        end
        def update_package_json_declaration(package_json_content:, new_req:, dependency_name:, old_req:)
          original_line = declaration_line(
            dependency_name: dependency_name,
            dependency_req: old_req,
            content: package_json_content
          )

          replacement_line = replacement_declaration_line(
            original_line: original_line,
            old_req: old_req,
            new_req: new_req
          )

          groups = (new_req.groups || []).map(&:to_s)

          update_package_json_sections(
            groups,
            package_json_content,
            original_line,
            replacement_line
          )
        end

        # For full details on how Yarn resolutions work, see
        # https://github.com/yarnpkg/rfcs/blob/master/implemented/
        # 0000-selective-versions-resolutions.md
        sig do
          params(
            package_json_content: String,
            new_req: Dependabot::DependencyRequirement,
            dependency: Dependabot::Dependency,
            old_req: T.nilable(Dependabot::DependencyRequirement)
          )
            .returns(String)
        end
        def update_package_json_resolutions(package_json_content:, new_req:, dependency:, old_req:)
          dep = dependency
          parsed_json_content = JSON.parse(package_json_content)
          resolutions =
            parsed_json_content.fetch("resolutions", parsed_json_content.dig("pnpm", "overrides") || {})
                               .reject { |_, v| v != old_req && v != dep.previous_version }
                               .select { |k, _| k == dep.name || k.end_with?("/#{dep.name}") }

          return package_json_content unless resolutions.any?

          content = package_json_content
          resolutions.each do |_, resolution|
            original_line = declaration_line(
              dependency_name: dep.name,
              dependency_req: requirement_declaration(resolution),
              content: content
            )

            new_resolution = resolution == old_req ? new_req.requirement : dep.version

            replacement_line = replacement_declaration_line(
              original_line: original_line,
              old_req: requirement_declaration(resolution),
              new_req: requirement_declaration(new_resolution)
            )

            content = update_package_json_sections(
              %w(resolutions overrides), content, original_line, replacement_line
            )
          end
          content
        end

        sig do
          params(
            sections: T::Array[String],
            content: String,
            old_line: String,
            new_line: String
          )
            .returns(String)
        end
        def update_package_json_sections(sections, content, old_line, new_line)
          # Currently, Dependabot doesn't update peerDependencies. However,
          # if a development dependency is being updated and its requirement
          # matches the requirement on a peer dependency we probably want to
          # update the peer too.
          #
          # TODO: Move this logic to the UpdateChecker (and parse peer deps)
          sections += ["peerDependencies"]
          sections_regex = /#{sections.join('|')}/

          declaration_blocks = T.let([], T::Array[String])

          content.scan(/['"]#{sections_regex}['"]\s*:\s*\{/m) do
            mtch = T.must(Regexp.last_match)
            declaration_blocks <<
              (mtch.to_s + T.must(mtch.post_match[0..closing_bracket_index(mtch.post_match)]))
          end

          declaration_blocks.reduce(content.dup) do |new_content, block|
            updated_block = block.sub(old_line, new_line)
            new_content.sub(block, updated_block)
          end
        end

        sig { params(string: String).returns(Integer) }
        def closing_bracket_index(string)
          closes_required = 1

          string.chars.each_with_index do |char, index|
            closes_required += 1 if char == "{"
            closes_required -= 1 if char == "}"
            return index if closes_required.zero?
          end

          0
        end

        sig { params(dependency: Dependabot::Dependency).void }
        def preliminary_check_for_update(dependency)
          T.must(dependency.previous_requirements).each do |req|
            requirement = req.requirement
            next unless requirement

            # some deps are patched with local patches, we don't need to update them
            if requirement.match?(Regexp.union(PATCH_PACKAGE))
              Dependabot.logger.info(
                "Func: updated_requirements. dependency patched #{dependency.name}," \
                " Requirement: '#{requirement}'"
              )

              raise DependencyFileNotResolvable,
                    "Dependency is patched locally, Update not required."
            end

            # some deps are added as local packages, we don't need to update them as they are referred to a local path
            next unless requirement.match?(Regexp.union(LOCAL_PACKAGE))

            Dependabot.logger.info(
              "Func: updated_requirements. local package #{dependency.name}," \
              " Requirement: '#{requirement}'"
            )

            raise DependencyFileNotResolvable,
                  "Local package, Update not required."
          end
        end
      end
    end
  end
end
