# frozen_string_literal: true

require "nokogiri"
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Java
      class Maven < Dependabot::FileUpdaters::Base
        require_relative "maven/declaration_finder"
        require_relative "maven/property_value_updater"

        def self.updated_files_regex
          [/^pom\.xml$/, %r{/pom\.xml$}]
        end

        def updated_dependency_files
          updated_files = pomfiles.dup

          # Loop through each of the changed requirements, applying changes to
          # all pomfiles for that change. Note that the logic is different here
          # to other languages because Java has property inheritance across
          # files
          dependencies.each do |dependency|
            updated_files = update_pomfiles_for_dependency(
              pomfiles: updated_files,
              dependency: dependency
            )
          end

          updated_files = updated_files.reject { |f| pomfiles.include?(f) }

          raise "No files changed!" if updated_files.none?
          if updated_files.any? { |f| f.name.end_with?("pom_parent.xml") }
            raise "Updated a supporting POM!"
          end
          updated_files
        end

        private

        def check_required_files
          raise "No pom.xml!" unless get_original_file("pom.xml")
        end

        def update_pomfiles_for_dependency(pomfiles:, dependency:)
          files = pomfiles.dup

          # The UpdateChecker ensures the order of requirements is preserved
          # when updating, so we can zip them together in new/old pairs.
          reqs = dependency.requirements.zip(dependency.previous_requirements).
                 reject { |new_req, old_req| new_req == old_req }

          # Loop through each changed requirement and update the pomfiles
          reqs.each do |new_req, old_req|
            raise "Bad req match" unless new_req[:file] == old_req[:file]
            next if new_req[:requirement] == old_req[:requirement]

            if new_req.dig(:metadata, :property_name)
              files = update_pomfiles_for_property_change(files, new_req)
              pom = files.find { |f| f.name == new_req.fetch(:file) }
              files[files.index(pom)] =
                remove_property_suffix_in_pom(dependency, pom, old_req)
            else
              pom = files.find { |f| f.name == new_req.fetch(:file) }
              files[files.index(pom)] =
                update_version_in_pom(dependency, pom, old_req, new_req)
            end
          end

          files
        end

        def update_pomfiles_for_property_change(pomfiles, req)
          property_name = req.fetch(:metadata).fetch(:property_name)

          PropertyValueUpdater.new(dependency_files: pomfiles).
            update_pomfiles_for_property_change(
              property_name: property_name,
              callsite_pom: pomfiles.find { |f| f.name == req.fetch(:file) },
              updated_value: req.fetch(:requirement)
            )
        end

        def update_version_in_pom(dependency, pom, previous_req, requirement)
          updated_content =
            pom.content.gsub(
              original_pom_declaration(dependency, previous_req),
              updated_pom_declaration(dependency, previous_req, requirement)
            )

          raise "Expected content to change!" if updated_content == pom.content
          updated_file(file: pom, content: updated_content)
        end

        def remove_property_suffix_in_pom(dep, pom, req)
          updated_content =
            pom.content.gsub(original_pom_declaration(dep, req)) do |old_dec|
              version_string =
                old_dec.match(%r{(?<=\<version\>).*(?=\</version\>)})
              cleaned_version_string = version_string.to_s.gsub(/(?<=\}).*/, "")

              old_dec.gsub(
                "<version>#{version_string}</version>",
                "<version>#{cleaned_version_string}</version>"
              )
            end

          updated_file(file: pom, content: updated_content)
        end

        def original_pom_declaration(dependency, requirement)
          declaration_finder(dependency, requirement).declaration_string
        end

        # The declaration finder may need to make remote calls (to get parent
        # POMs if it's searching for the value of a property), so we cache it.
        def declaration_finder(dependency, requirement)
          @declaration_finders ||= {}
          @declaration_finders[dependency.hash + requirement.hash] ||=
            begin
              DeclarationFinder.new(
                dependency: dependency,
                declaring_requirement: requirement,
                dependency_files: dependency_files
              )
            end
        end

        def updated_pom_declaration(dependency, previous_req, requirement)
          original_req_string = previous_req.fetch(:requirement)

          original_pom_declaration(dependency, previous_req).gsub(
            %r{<version>\s*#{Regexp.quote(original_req_string)}\s*</version>},
            "<version>#{requirement.fetch(:requirement)}</version>"
          )
        end

        def pomfiles
          @pomfiles ||=
            dependency_files.select { |f| f.name.end_with?("pom.xml") }
        end
      end
    end
  end
end
