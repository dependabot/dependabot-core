# frozen_string_literal: true

require "python_requirement_parser"
require "dependabot/file_updaters/base"
require "dependabot/file_parsers/python/pip"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Python
      class Pip < Dependabot::FileUpdaters::Base
        require_relative "pip/pipfile_file_updater"
        require_relative "pip/pip_compile_file_updater"

        def self.updated_files_regex
          [
            /^Pipfile$/,
            /^Pipfile\.lock$/,
            /requirements.*\.txt$/,
            /^constraints\.txt$/,
            /^setup\.py$/,
            /requirements.*\.in$/
          ]
        end

        def updated_dependency_files
          case resolver_type
          when :pipfile then updated_pipfile_based_files
          when :pip_compile then updated_pip_compile_based_files
          when :requirements then updated_requirement_based_files
          else raise "Unexpected resolver type: #{resolver_type}"
          end
        end

        private

        def resolver_type
          reqs = dependencies.flat_map(&:requirements)

          if (pipfile && reqs.none?) ||
             reqs.any? { |r| r.fetch(:file) == "Pipfile" }
            return :pipfile
          end

          if (pip_compile_files.any? && reqs.none?) ||
             reqs.any? { |r| r.fetch(:file).end_with?(".in") }
            return :pip_compile
          end

          :requirements
        end

        def updated_pipfile_based_files
          PipfileFileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          ).updated_dependency_files
        end

        def updated_pip_compile_based_files
          PipCompileFileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          ).updated_dependency_files
        end

        def updated_requirement_based_files
          updated_files = []

          changed_requirements =
            dependency.requirements - dependency.previous_requirements

          changed_requirements.each do |req|
            updated_files << updated_file(
              file: original_file(req.fetch(:file)),
              content: updated_requirement_or_setup_file_content(req)
            )
          end

          updated_files
        end

        def dependency
          # For now, we'll only ever be updating a single dependency for Python
          dependencies.first
        end

        def check_required_files
          filenames = dependency_files.map(&:name)
          return if filenames.any? { |name| name.match?(/requirements/x) }
          return if (%w(Pipfile Pipfile.lock) - filenames).empty?
          return if get_original_file("setup.py")
          raise "No requirements.txt or setup.py!"
        end

        def original_file(filename)
          get_original_file(filename)
        end

        def updated_requirement_or_setup_file_content(requirement)
          content = original_file(requirement.fetch(:file)).content

          updated_content =
            content.gsub(
              original_dependency_declaration_string(requirement),
              updated_dependency_declaration_string(requirement)
            )

          raise "Expected content to change!" if content == updated_content
          updated_content
        end

        def original_dependency_declaration_string(requirements)
          regex = PythonRequirementParser::INSTALL_REQ_WITH_REQUIREMENT
          matches = []

          original_file(requirements.fetch(:file)).
            content.scan(regex) { matches << Regexp.last_match }
          dec = matches.find { |m| normalise(m[:name]) == dependency.name }
          raise "Declaration not found for #{dependency.name}!" unless dec
          dec.to_s
        end

        def updated_dependency_declaration_string(requirement)
          updated_string =
            original_dependency_declaration_string(requirement).sub(
              PythonRequirementParser::REQUIREMENTS,
              requirement.fetch(:requirement)
            )

          return updated_string unless requirement_includes_hashes?(requirement)

          updated_string.sub(
            PythonRequirementParser::HASHES,
            package_hashes_for(
              name: dependency.name,
              version: dependency.version,
              algorithm: hash_algorithm(requirement)
            ).join(hash_separator(requirement))
          )
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
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/python/run.py")
        end

        def pipfile
          @pipfile ||= get_original_file("Pipfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Pipfile.lock")
        end

        def pip_compile_files
          dependency_files.select { |f| f.name.end_with?(".in") }
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalise(name)
          name.downcase.tr("_", "-").tr(".", "-")
        end
      end
    end
  end
end
