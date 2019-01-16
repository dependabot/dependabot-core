# frozen_string_literal: true

require "dependabot/npm_and_yarn/file_updater"

module Dependabot
  module NpmAndYarn
    class FileUpdater
      class PackageJsonUpdater
        def initialize(package_json:, dependencies:)
          @package_json = package_json
          @dependencies = dependencies
        end

        def updated_package_json
          updated_file = package_json.dup
          updated_file.content = updated_package_json_content
          updated_file
        end

        private

        attr_reader :package_json, :dependencies

        def updated_package_json_content
          dependencies.reduce(package_json.content.dup) do |content, dep|
            updated_requirements(dep).each do |new_req|
              old_req = old_requirement(dep, new_req)

              new_content = update_package_json_declaration(
                package_json_content: content,
                dependency_name: dep.name,
                old_req: old_req,
                new_req: new_req
              )

              raise "Expected content to change!" if content == new_content

              content = new_content
            end

            new_requirements(dep).each do |new_req|
              old_req = old_requirement(dep, new_req)

              content = update_package_json_resolutions(
                package_json_content: content,
                new_req: new_req,
                dependency: dep,
                old_req: old_req
              )
            end

            content
          end
        end

        def old_requirement(dependency, new_requirement)
          dependency.previous_requirements.
            select { |r| r[:file] == package_json.name }.
            find { |r| r[:groups] == new_requirement[:groups] }
        end

        def new_requirements(dependency)
          dependency.requirements.select { |r| r[:file] == package_json.name }
        end

        def updated_requirements(dependency)
          new_requirements(dependency).
            reject { |r| dependency.previous_requirements.include?(r) }
        end

        def update_package_json_declaration(package_json_content:, new_req:,
                                            dependency_name:, old_req:)
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
        def update_package_json_resolutions(package_json_content:, new_req:,
                                            dependency:, old_req:)
          dep = dependency
          resolutions =
            JSON.parse(package_json_content).fetch("resolutions", {}).
            reject { |_, v| v != old_req && v != dep.previous_version }.
            select { |k, _| k == dep.name || k.end_with?("/#{dep.name}") }

          return package_json_content unless resolutions.any?

          content = package_json_content
          resolutions.each do |_, resolution|
            original_line = declaration_line(
              dependency_name: dep.name,
              dependency_req: { requirement: resolution },
              content: content
            )

            new_resolution = resolution == old_req ? new_req : dep.version

            replacement_line = replacement_declaration_line(
              original_line: original_line,
              old_req: { requirement: resolution },
              new_req: { requirement: new_resolution }
            )

            content = update_package_json_sections(
              ["resolutions"], content, original_line, replacement_line
            )
          end
          content
        end

        def declaration_line(dependency_name:, dependency_req:, content:)
          git_dependency = dependency_req.dig(:source, :type) == "git"

          unless git_dependency
            requirement = dependency_req.fetch(:requirement)
            return content.match(/"#{Regexp.escape(dependency_name)}"\s*:\s*
                                  "#{Regexp.escape(requirement)}"/x).to_s
          end

          username, repo =
            dependency_req.dig(:source, :url).split("/").last(2)

          content.match(
            %r{"#{Regexp.escape(dependency_name)}"\s*:\s*
               ".*?#{Regexp.escape(username)}/#{Regexp.escape(repo)}.*"}x
          ).to_s
        end

        def replacement_declaration_line(original_line:, old_req:, new_req:)
          was_git_dependency = old_req.dig(:source, :type) == "git"
          now_git_dependency = new_req.dig(:source, :type) == "git"

          unless was_git_dependency
            return original_line.gsub(
              %("#{old_req.fetch(:requirement)}"),
              %("#{new_req.fetch(:requirement)}")
            )
          end

          unless now_git_dependency
            return original_line.gsub(
              /(?<=\s").*[^\\](?=")/,
              new_req.fetch(:requirement)
            )
          end

          if original_line.include?("semver:")
            return original_line.gsub(
              %(semver:#{old_req.fetch(:requirement)}"),
              %(semver:#{new_req.fetch(:requirement)}")
            )
          end

          original_line.gsub(
            %(\##{old_req.dig(:source, :ref)}"),
            %(\##{new_req.dig(:source, :ref)}")
          )
        end

        def update_package_json_sections(sections, content, old_line,
                                         new_line)
          # Currently, Dependabot doesn't update peerDependencies. However,
          # if a development dependency is being updated and its requirement
          # matches the requirement on a peer dependency we probably want to
          # update the peer too.
          #
          # TODO: Move this logic to the UpdateChecker (and parse peer deps)
          sections += ["peerDependencies"]
          sections_regex = /#{sections.join("|")}/

          declaration_blocks = []

          content.scan(/['"]#{sections_regex}['"]\s*:\s*\{/m) do
            mtch = Regexp.last_match
            declaration_blocks <<
              mtch.to_s +
              mtch.post_match[0..closing_bracket_index(mtch.post_match)]
          end

          declaration_blocks.reduce(content.dup) do |new_content, block|
            updated_block = block.sub(old_line, new_line)
            new_content.sub!(block, updated_block)
          end
        end

        def closing_bracket_index(string)
          closes_required = 1

          string.chars.each_with_index do |char, index|
            closes_required += 1 if char == "{"
            closes_required -= 1 if char == "}"
            return index if closes_required.zero?
          end
        end
      end
    end
  end
end
