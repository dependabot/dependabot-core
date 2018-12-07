# frozen_string_literal: true

require "python_requirement_parser"
require "dependabot/python/file_updater"
require "dependabot/shared_helpers"

module Dependabot
  module Python
    class FileUpdater
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
          reqs = dependency.requirements.zip(dependency.previous_requirements)

          reqs.map do |(new_req, old_req)|
            next if new_req == old_req

            file = get_original_file(new_req.fetch(:file)).dup
            updated_content =
              updated_requirement_or_setup_file_content(new_req, old_req)
            next if updated_content == file.content

            file.content = updated_content
            file
          end.compact
        end

        def updated_requirement_or_setup_file_content(new_req, old_req)
          content = get_original_file(new_req.fetch(:file)).content

          updated_content =
            content.gsub(
              original_declaration_replacement_regex(old_req),
              updated_dependency_declaration_string(new_req, old_req)
            )

          raise "Expected content to change!" if content == updated_content

          updated_content
        end

        def original_dependency_declaration_string(requirement)
          regex = PythonRequirementParser::INSTALL_REQ_WITH_REQUIREMENT
          matches = []

          get_original_file(requirement.fetch(:file)).
            content.scan(regex) { matches << Regexp.last_match }
          dec = matches.
                select { |m| normalise(m[:name]) == dependency.name }.
                find do |m|
                  # The FileParser can mess up a requirement's spacing so we
                  # sanitize both requirements before comparing
                  f_req = m[:requirements]&.gsub(/\s/, "")&.split(",")&.sort
                  p_req = requirement.fetch(:requirement)&.
                          gsub(/\s/, "")&.split(",")&.sort
                  f_req == p_req
                end

          raise "Declaration not found for #{dependency.name}!" unless dec

          dec.to_s.strip
        end

        def updated_dependency_declaration_string(new_req, old_req)
          updated_string =
            original_dependency_declaration_string(old_req).sub(
              PythonRequirementParser::REQUIREMENTS,
              new_req.fetch(:requirement)
            )
          return updated_string unless requirement_includes_hashes?(old_req)

          updated_string.sub(
            PythonRequirementParser::HASHES,
            package_hashes_for(
              name: dependency.name,
              version: dependency.version,
              algorithm: hash_algorithm(old_req)
            ).join(hash_separator(old_req))
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
          current_separator =
            original_dependency_declaration_string(requirement).
            match(/#{hash_regex}((?<separator>\s*\\?\s*?)#{hash_regex})*/).
            named_captures.fetch("separator")

          default_separator =
            original_dependency_declaration_string(requirement).
            match(PythonRequirementParser::HASH).
            pre_match.match(/(?<separator>\s*\\?\s*?)\z/).
            named_captures.fetch("separator")

          current_separator || default_separator
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
          name.downcase.gsub(/[-_.]+/, "-")
        end

        def get_original_file(filename)
          dependency_files.find { |f| f.name == filename }
        end
      end
    end
  end
end
