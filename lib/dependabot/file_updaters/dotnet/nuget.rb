# frozen_string_literal: true

require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Dotnet
      class Nuget < Dependabot::FileUpdaters::Base
        require_relative "nuget/packages_config_declaration_finder"
        require_relative "nuget/project_file_declaration_finder"

        def self.updated_files_regex
          [%r{^[^/]*\.csproj$}]
        end

        def updated_dependency_files
          updated_files = project_files.dup
          updated_files << packages_config.dup if packages_config

          # Loop through each of the changed requirements, applying changes to
          # all files for that change. Note that the logic is different here
          # to other languages because donet has property inheritance across
          # files
          dependencies.each do |dependency|
            updated_files = update_files_for_dependency(
              files: updated_files,
              dependency: dependency
            )
          end

          updated_files.reject! { |f| dependency_files.include?(f) }

          raise "No files changed!" if updated_files.none?
          updated_files
        end

        private

        def project_files
          dependency_files.select { |df| df.name.match?(/\.(cs|vb|fs)proj$/) }
        end

        def packages_config
          dependency_files.find { |df| df.name == "packages.config" }
        end

        def check_required_files
          return if project_files.any? || packages_config
          raise "No project file or packages.config!"
        end

        def update_files_for_dependency(files:, dependency:)
          files = files.dup

          # The UpdateChecker ensures the order of requirements is preserved
          # when updating, so we can zip them together in new/old pairs.
          reqs = dependency.requirements.zip(dependency.previous_requirements).
                 reject { |new_req, old_req| new_req == old_req }

          # Loop through each changed requirement and update the files
          reqs.each do |new_req, old_req|
            raise "Bad req match" unless new_req[:file] == old_req[:file]
            next if new_req[:requirement] == old_req[:requirement]

            file = files.find { |f| f.name == new_req.fetch(:file) }
            files[files.index(file)] =
              update_version_in_file(dependency, file, old_req, new_req)
          end

          files
        end

        def update_version_in_file(dependency, file, old_req, new_req)
          updated_content = file.content

          original_declarations(dependency, old_req).each do |old_dec|
            updated_content = updated_content.gsub(
              old_dec,
              updated_declaration(old_dec, old_req, new_req)
            )
          end

          raise "Expected content to change!" if updated_content == file.content
          updated_file(file: file, content: updated_content)
        end

        def original_declarations(dependency, requirement)
          declaration_finder(dependency, requirement).declaration_strings
        end

        def declaration_finder(dependency, requirement)
          @declaration_finders ||= {}
          @declaration_finders[dependency.hash + requirement.hash] ||=
            if requirement.fetch(:file) == "packages.config"
              PackagesConfigDeclarationFinder.new(
                dependency_name: dependency.name,
                declaring_requirement: requirement,
                packages_config: packages_config
              )
            else
              ProjectFileDeclarationFinder.new(
                dependency_name: dependency.name,
                declaring_requirement: requirement,
                dependency_files: dependency_files
              )
            end
        end

        def updated_declaration(old_declaration, previous_req, requirement)
          original_req_string = previous_req.fetch(:requirement)

          old_declaration.gsub(
            original_req_string,
            requirement.fetch(:requirement)
          )
        end
      end
    end
  end
end
