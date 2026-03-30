# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/npm_and_yarn/file_updater"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      # This updater intentionally keeps declaration, resolution, and override rewrites together
      # because they share the same string-based package.json editing primitives.
      # rubocop:disable Metrics/ClassLength
      class PackageJsonUpdater
        extend T::Sig

        require_relative "package_json_updater/pnpm_override_helper"
        LOCAL_PACKAGE = T.let([/portal:/, /file:/].freeze, T::Array[Regexp])
        PATCH_PACKAGE = T.let([/patch:/].freeze, T::Array[Regexp])

        sig do
          params(
            package_json: Dependabot::DependencyFile,
            dependencies: T::Array[Dependabot::Dependency],
            detected_package_manager: T.nilable(String)
          ).void
        end
        def initialize(package_json:, dependencies:, detected_package_manager: nil)
          @package_json = package_json
          @dependencies = dependencies
          @detected_package_manager = detected_package_manager
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
        attr_reader :detected_package_manager

        sig { returns(T.nilable(String)) }
        def updated_package_json_content
          # checks if we are updating single dependency in package.json
          unique_deps_count = dependencies.map(&:name).to_a.uniq.compact.length

          dependencies.reduce(package_json.content.dup) do |content, dep|
            apply_dependency_updates(content: T.must(content), dependency: dep, unique_deps_count: unique_deps_count)
          end
        end

        sig do
          params(content: String, dependency: Dependabot::Dependency, unique_deps_count: Integer)
            .returns(String)
        end
        def apply_dependency_updates(content:, dependency:, unique_deps_count:)
          content = apply_requirement_updates(
            content: content,
            dependency: dependency,
            unique_deps_count: unique_deps_count
          )
          content = apply_resolution_updates(content: content, dependency: dependency)
          return content unless dependency.previous_version && new_requirements(dependency).empty?

          apply_subdependency_updates(content: content, dependency: dependency)
        end

        sig do
          params(content: String, dependency: Dependabot::Dependency, unique_deps_count: Integer)
            .returns(String)
        end
        def apply_requirement_updates(content:, dependency:, unique_deps_count:)
          updated_requirements(dependency)&.each do |new_req|
            new_content = update_package_json_declaration(
              package_json_content: content,
              dependency_name: dependency.name,
              old_req: old_requirement(dependency, new_req),
              new_req: new_req
            )

            # package.json does not always contain the same dependencies as the parsed dependency list.
            # For example, the parsed data can contain "dep" => "1.0.0" and "dev" => "1.0.1" while
            # package.json only contains "dep" => "1.0.0". For a single unique dependency name we
            # tolerate that no-op, but for multiple unique dependencies we treat it as unexpected and raise.
            raise "Expected content to change!" if content == new_content && unique_deps_count > 1

            content = new_content
          end

          content
        end

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def apply_resolution_updates(content:, dependency:)
          new_requirements(dependency).each do |new_req|
            content = update_package_json_resolutions(
              package_json_content: content,
              new_req: new_req,
              dependency: dependency,
              old_req: old_requirement(dependency, new_req)
            )
          end

          content
        end

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def apply_subdependency_updates(content:, dependency:)
          updated_content = update_overrides_for_subdependency(
            package_json_content: content,
            dependency: dependency
          )
          return updated_content unless updated_content == content

          PnpmOverrideHelper.new(
            package_json_content: content,
            dependency: dependency,
            detected_package_manager: detected_package_manager
          ).updated_content
        end

        sig do
          params(
            dependency: Dependabot::Dependency,
            new_requirement: T::Hash[Symbol, T.untyped]
          )
            .returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def old_requirement(dependency, new_requirement)
          T.must(dependency.previous_requirements)
           .select { |r| r[:file] == package_json.name }
           .find { |r| r[:groups] == new_requirement[:groups] }
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def new_requirements(dependency)
          dependency.requirements.select { |r| r[:file] == package_json.name }
        end

        sig { params(dependency: Dependabot::Dependency).returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
        def updated_requirements(dependency)
          return unless dependency.previous_requirements

          preliminary_check_for_update(dependency)

          updated_requirement_pairs =
            dependency.requirements.zip(T.must(dependency.previous_requirements))
                      .reject do |new_req, old_req|
              next true if new_req == old_req
              next false unless old_req&.fetch(:source).nil?

              new_req[:requirement] == old_req&.fetch(:requirement)
            end

          updated_requirement_pairs
            .map(&:first)
            .select { |r| r[:file] == package_json.name }
        end

        sig do
          params(
            package_json_content: String,
            new_req: T::Hash[Symbol, T.untyped],
            dependency_name: String,
            old_req: T.nilable(T::Hash[Symbol, T.untyped])
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

          groups = new_req.fetch(:groups)

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
            new_req: T::Hash[Symbol, T.untyped],
            dependency: Dependabot::Dependency,
            old_req: T.nilable(T::Hash[Symbol, T.untyped])
          )
            .returns(String)
        end
        def update_package_json_resolutions(package_json_content:, new_req:, dependency:, old_req:)
          dep = dependency
          resolutions = matching_resolutions(package_json_content, dep, old_req)

          return package_json_content unless resolutions.any?

          content = package_json_content
          resolutions.each do |_, resolution|
            original_line = declaration_line(
              dependency_name: dep.name,
              dependency_req: { requirement: resolution },
              content: content
            )

            new_resolution = resolution == old_req&.dig(:requirement) ? new_req.fetch(:requirement) : dep.version

            replacement_line = replacement_declaration_line(
              original_line: original_line,
              old_req: { requirement: resolution },
              new_req: { requirement: new_resolution }
            )

            content = update_package_json_sections(
              %w(resolutions overrides), content, original_line, replacement_line
            )
          end
          content
        end

        sig { params(package_json_content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_overrides_for_subdependency(package_json_content:, dependency:)
          parsed = JSON.parse(package_json_content)
          entries = resolution_entries(parsed)
          return package_json_content unless entries.any?

          matching = entries
                     .select { |_, v| v.is_a?(String) }
                     .select { |k, _| k == dependency.name || k.end_with?("/#{dependency.name}") }
                     .select { |_, v| v.include?(T.must(dependency.previous_version)) }
          return package_json_content unless matching.any?

          content = package_json_content
          matching.each do |_, resolution|
            original_line = declaration_line(
              dependency_name: dependency.name,
              dependency_req: { requirement: resolution },
              content: content
            )

            new_resolution = resolution.sub(T.must(dependency.previous_version), T.must(dependency.version))

            replacement_line = replacement_declaration_line(
              original_line: original_line,
              old_req: { requirement: resolution },
              new_req: { requirement: new_resolution }
            )

            content = update_package_json_sections(
              %w(resolutions overrides), content, original_line, replacement_line
            )
          end
          content
        end

        sig do
          params(
            package_json_content: String,
            dep: Dependabot::Dependency,
            old_req: T.nilable(T::Hash[Symbol, T.untyped])
          )
            .returns(T::Hash[String, String])
        end
        def matching_resolutions(package_json_content, dep, old_req)
          parsed = JSON.parse(package_json_content)
          old_requirement = old_req&.dig(:requirement)

          resolution_entries(parsed)
            .select { |_, v| v.is_a?(String) }
            .select { |_, v| v == old_requirement || v == dep.previous_version }
            .select { |k, _| k == dep.name || k.end_with?("/#{dep.name}") }
        end

        sig { params(parsed: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
        def resolution_entries(parsed)
          parsed["resolutions"] ||
            parsed["overrides"] ||
            parsed.dig("pnpm", "overrides") ||
            {}
        end

        sig do
          params(
            dependency_name: String,
            dependency_req: T.nilable(T::Hash[Symbol, T.untyped]),
            content: String
          )
            .returns(String)
        end
        def declaration_line(dependency_name:, dependency_req:, content:)
          git_dependency = dependency_req&.dig(:source, :type) == "git"

          unless git_dependency
            requirement = dependency_req&.fetch(:requirement)
            return content.match(
              /"#{Regexp.escape(dependency_name)}"\s*:\s*
                                                "#{Regexp.escape(requirement)}"/x
            ).to_s
          end

          username, repo =
            dependency_req&.dig(:source, :url)&.split("/")&.last(2)

          content.match(
            %r{"#{Regexp.escape(dependency_name)}"\s*:\s*
               ".*?#{Regexp.escape(username)}/#{Regexp.escape(repo)}.*"}x
          ).to_s
        end

        sig do
          params(
            original_line: String,
            old_req: T.nilable(T::Hash[Symbol, T.untyped]),
            new_req: T::Hash[Symbol, T.untyped]
          )
            .returns(String)
        end
        def replacement_declaration_line(original_line:, old_req:, new_req:)
          was_git_dependency = old_req&.dig(:source, :type) == "git"
          now_git_dependency = new_req.dig(:source, :type) == "git"

          unless was_git_dependency
            return original_line.gsub(
              %("#{old_req&.fetch(:requirement)}"),
              %("#{new_req.fetch(:requirement)}")
            )
          end

          unless now_git_dependency
            return original_line.gsub(
              /(?<=\s").*[^\\](?=")/,
              new_req.fetch(:requirement)
            )
          end

          if original_line.match?(/#[\^~=<>]|semver:/)
            return update_git_semver_requirement(
              original_line: original_line,
              old_req: old_req,
              new_req: new_req
            )
          end

          original_line.gsub(
            %(##{old_req&.dig(:source, :ref)}"),
            %(##{new_req.dig(:source, :ref)}")
          )
        end

        sig do
          params(
            original_line: String,
            old_req: T.nilable(T::Hash[Symbol, String]),
            new_req: T::Hash[Symbol, String]
          )
            .returns(String)
        end
        def update_git_semver_requirement(original_line:, old_req:, new_req:)
          if original_line.include?("semver:")
            return original_line.gsub(
              %(semver:#{old_req&.fetch(:requirement)}"),
              %(semver:#{new_req.fetch(:requirement)}")
            )
          end

          raise "Not a semver req!" unless original_line.match?(/#[\^~=<>]/)

          original_line.gsub(
            %(##{old_req&.fetch(:requirement)}"),
            %(##{new_req.fetch(:requirement)}")
          )
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
          T.must(dependency.previous_requirements).each do |req, _dep|
            next if req.fetch(:requirement).nil?

            # some deps are patched with local patches, we don't need to update them
            if req.fetch(:requirement).match?(Regexp.union(PATCH_PACKAGE))
              Dependabot.logger.info(
                "Func: updated_requirements. dependency patched #{dependency.name}," \
                " Requirement: '#{req.fetch(:requirement)}'"
              )

              raise DependencyFileNotResolvable,
                    "Dependency is patched locally, Update not required."
            end

            # some deps are added as local packages, we don't need to update them as they are referred to a local path
            next unless req.fetch(:requirement).match?(Regexp.union(LOCAL_PACKAGE))

            Dependabot.logger.info(
              "Func: updated_requirements. local package #{dependency.name}," \
              " Requirement: '#{req.fetch(:requirement)}'"
            )

            raise DependencyFileNotResolvable,
                  "Local package, Update not required."
          end
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
