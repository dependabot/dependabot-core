# typed: true
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Nuget
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/packages_config_declaration_finder"
      require_relative "file_updater/project_file_declaration_finder"
      require_relative "file_updater/property_value_updater"

      def self.updated_files_regex
        [
          %r{^[^/]*\.[a-z]{2}proj$},
          /^packages\.config$/i,
          /^global\.json$/i,
          /^dotnet-tools\.json$/i,
          /^Directory\.Build\.props$/i,
          /^Directory\.Build\.targets$/i,
          /^Packages\.props$/i
        ]
      end

      def updated_dependency_files
        updated_files = T.let(dependency_files.dup, T.untyped)

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
        dependency_files.select { |df| df.name.match?(/\.[a-z]{2}proj$|[Dd]irectory.[Pp]ackages.props/) }
      end

      def packages_config_files
        dependency_files.select do |f|
          T.must(T.must(f.name.split("/").last).casecmp("packages.config")).zero?
        end
      end

      def global_json
        dependency_files.find { |f| T.must(f.name.casecmp("global.json")).zero? }
      end

      def dotnet_tools_json
        dependency_files.find { |f| T.must(f.name.casecmp(".config/dotnet-tools.json")).zero? }
      end

      def check_required_files
        return if project_files.any? || packages_config_files.any?

        raise "No project file or packages.config!"
      end

      def update_files_for_dependency(files:, dependency:)
        # The UpdateChecker ensures the order of requirements is preserved
        # when updating, so we can zip them together in new/old pairs.
        reqs = dependency.requirements.zip(dependency.previous_requirements)
                         .reject { |new_req, old_req| new_req == old_req }

        # Loop through each changed requirement and update the files
        reqs.each do |new_req, old_req|
          raise "Bad req match" unless new_req[:file] == old_req[:file]
          next if new_req[:requirement] == old_req[:requirement]

          file = files.find { |f| f.name == new_req.fetch(:file) }

          files =
            if new_req.dig(:metadata, :property_name)
              update_property_value(files, file, new_req)
            else
              update_declaration(files, dependency, file, old_req, new_req)
            end
        end

        files
      end

      def update_property_value(files, file, req)
        files = files.dup
        property_name = req.fetch(:metadata).fetch(:property_name)

        PropertyValueUpdater
          .new(dependency_files: files)
          .update_files_for_property_change(
            property_name: property_name,
            updated_value: req.fetch(:requirement),
            callsite_file: file
          )
      end

      def insert_new_declaration(file_content, declaration_name, declaration_version)
        new_package_reference = "<PackageReference Include=\"#{declaration_name}\" Version=\"#{declaration_version}\" />"

        # guess at kind of newlines we should use when modifying the file
        # if there are mixed newlines we will use \r\n
        newline = file_content.include?("\r\n") ? "\r\n" : "\n"
        # Determine if the file uses tabs or spaces for indentation
        indent_regex = /^(\s+)/
        indent_match = file_content.match(indent_regex)
        use_tabs = indent_match[1].include?("\t")

        # attempt to find any existing item group in the file
        item_group_regex = /<ItemGroup>((\r\n|\n)(\s*).*\S)*(\r\n|\n)/m
        match = file_content.match(item_group_regex)

        if match
          # found an ItemGroup
          indent_regex = /^([ \t]+)/
          item_group_indent_match = match[0].match(indent_regex)
          item_group_indentation = item_group_indent_match[1]

          # Look for the last element inside the ItemGroup
          last_element_regex = %r{(\r\n|\n)(\s*).*\S(?=(\r\n|\n)\s*</ItemGroup>)}
          last_element_match = match[0].match(last_element_regex)

          # use whatever indentation elements in the ItemGroup are using
          # else, fall back to the indentation level of the item group itself
          # and use the know tab or space character, defaulting to two spaces
          if last_element_match
            element_indent_match = last_element_match[0].match(indent_regex)
            element_indentation = element_indent_match[1]
          else
            element_indentation = item_group_indentation + (use_tabs ? "\t" : "  ")
          end

          new_line_with_indentation = "#{element_indentation}#{new_package_reference}#{newline}"
          file_content.sub(match[0],
                           match[0].sub("</ItemGroup>",
                                        "#{new_line_with_indentation}#{item_group_indentation}</ItemGroup>"))
        else
          # need to create a new item group
          # first find the project element
          project_end_regex = %r{</Project>((\r\n|\n))?}m
          match = file_content.match(project_end_regex)
          if match
            indent_regex = /^([ \t]+)/
            # then find the property group element and use that to try and determine the indentation
            indent_match = file_content.match(%r{.*</PropertyGroup>}m)[0].match(indent_regex)
            indentation = if indent_match
                            indent_match[1]
                          else
                            (use_tabs ? "\t" : "  ")
                          end

            # insert our new item group between the last property group and then end of the project
            item_group = "#{newline}#{indentation}<ItemGroup>#{newline}#{indentation}#{indentation}#{new_package_reference}#{newline}#{indentation}</ItemGroup>"
            # replace the </Project> element with our item group ensuring we append the final newline if
            # it exists
            file_content.sub(project_end_regex, item_group + "#{newline}</Project>#{match[1]}")
          end
        end
      end

      def update_declaration(files, dependency, file, old_req, new_req)
        files = files.dup

        updated_content = file.content

        original_declarations(dependency, old_req).each do |old_dec|
          updated_content = updated_content.gsub(
            old_dec,
            updated_declaration(old_dec, old_req, new_req)
          )
        end

        if updated_content == file.content
          # append new package reference to project file
          updated_content = insert_new_declaration(updated_content, dependency.name, new_req[:requirement])
        end

        raise "Expected content to change!" if updated_content == file.content

        files[files.index(file)] =
          updated_file(file: file, content: updated_content)
        files
      end

      def original_declarations(dependency, requirement)
        if requirement.fetch(:file).casecmp("global.json").zero?
          [
            global_json.content.match(
              /"#{Regexp.escape(dependency.name)}"\s*:\s*
               "#{Regexp.escape(dependency.previous_version)}"/x
            ).to_s
          ]
        elsif requirement.fetch(:file).casecmp(".config/dotnet-tools.json").zero?
          [
            dotnet_tools_json.content.match(
              /"#{Regexp.escape(dependency.name)}"\s*:\s*{\s*"version"\s*:\s*
               "#{Regexp.escape(dependency.previous_version)}"/xm
            ).to_s
          ]
        else
          declaration_finder(dependency, requirement).declaration_strings
        end
      end

      def declaration_finder(dependency, requirement)
        @declaration_finders ||= {}

        requirement_fn = requirement.fetch(:file)
        @declaration_finders[dependency.hash + requirement.hash] ||=
          if requirement_fn.split("/").last.casecmp("packages.config").zero?
            PackagesConfigDeclarationFinder.new(
              dependency_name: dependency.name,
              declaring_requirement: requirement,
              packages_config:
                packages_config_files.find { |f| f.name == requirement_fn }
            )
          else
            ProjectFileDeclarationFinder.new(
              dependency_name: dependency.name,
              declaring_requirement: requirement,
              dependency_files: dependency_files,
              credentials: credentials
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

Dependabot::FileUpdaters.register("nuget", Dependabot::Nuget::FileUpdater)
