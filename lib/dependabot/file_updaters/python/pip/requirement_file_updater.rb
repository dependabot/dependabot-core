# frozen_string_literal: true

require "python_requirement_parser"
require "dependabot/file_updaters/python/pip"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Python
      class Pip
        class RequirementFileUpdater
          attr_reader :dependencies, :dependency_files, :credentials

          def initialize(dependencies:, dependency_files:, credentials:)
            @dependencies = dependencies
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def updated_dependency_files
            return @updated_dependency_files if @update_already_attempted

            @update_already_attempted = true
            @updated_dependency_files ||= fetch_updated_dependency_files
          end

          private

          def dependency
            # For now, we'll only ever be updating a single dependency
            dependencies.first
          end

          def fetch_updated_dependency_files
            changed_requirements =
              dependency.requirements - dependency.previous_requirements

            changed_requirements.
              map do |req|
                file = get_original_file(req.fetch(:file)).dup
                updated_content = updated_requirement_or_setup_file_content(req)
                next if updated_content == file.content
                file.content = updated_content
                file
              end.compact
          end

          def updated_requirement_or_setup_file_content(requirement)
            content = get_original_file(requirement.fetch(:file)).content

            updated_content =
              content.gsub(
                original_declaration_replacement_regex(requirement),
                updated_dependency_declaration_string(requirement)
              )

            raise "Expected content to change!" if content == updated_content
            updated_content
          end

          def original_dependency_declaration_string(requirement)
            regex = PythonRequirementParser::INSTALL_REQ_WITH_REQUIREMENT
            matches = []

            get_original_file(requirement.fetch(:file)).
              content.scan(regex) { matches << Regexp.last_match }
            dec = matches.find { |m| normalise(m[:name]) == dependency.name }
            raise "Declaration not found for #{dependency.name}!" unless dec
            dec.to_s.strip
          end

          def updated_dependency_declaration_string(requirement)
            updated_string =
              original_dependency_declaration_string(requirement).sub(
                PythonRequirementParser::REQUIREMENTS,
                requirement.fetch(:requirement)
              )

            unless requirement_includes_hashes?(requirement)
              return updated_string
            end

            updated_string.sub(
              PythonRequirementParser::HASHES,
              package_hashes_for(
                name: dependency.name,
                version: dependency.version,
                algorithm: hash_algorithm(requirement)
              ).join(hash_separator(requirement))
            )
          end

          def original_declaration_replacement_regex(requirement)
            original_string =
              original_dependency_declaration_string(requirement)
            /(?<![\-\w])#{Regexp.escape(original_string)}(?![\-\w])/
          end

          def requirement_includes_hashes?(requirement)
            original_dependency_declaration_string(requirement).
              match?(PythonRequirementParser::HASHES)
          end

          def hash_algorithm(requirement)
            return unless requirement_includes_hashes?(requirement)
            original_dependency_declaration_string(requirement).
              match(PythonRequirementParser::HASHES).
              named_captures.fetch("algorithm")
          end

          def hash_separator(requirement)
            return unless requirement_includes_hashes?(requirement)

            hash_regex = PythonRequirementParser::HASH
            original_dependency_declaration_string(requirement).
              match(/#{hash_regex}((?<separator>\s*\\?\s*?)#{hash_regex})*/).
              named_captures.fetch("separator")
          end

          def package_hashes_for(name:, version:, algorithm:)
            SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python #{python_helper_path}",
              function: "get_dependency_hash",
              args: [name, version, algorithm]
            ).map { |h| "--hash=#{algorithm}:#{h['hash']}" }
          end

          def python_helper_path
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/python/run.py")
          end

          # See https://www.python.org/dev/peps/pep-0503/#normalized-names
          def normalise(name)
            name.downcase.tr("_", "-").tr(".", "-")
          end

          def get_original_file(filename)
            dependency_files.find { |f| f.name == filename }
          end
        end
      end
    end
  end
end
