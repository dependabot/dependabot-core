# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/maven/file_updater"
require "dependabot/maven/file_parser/property_value_finder"

module Dependabot
  module Maven
    class FileUpdater
      class PropertyValueUpdater
        extend T::Sig

        sig { params(dependency_files: T::Array[DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        sig do
          params(
            property_name: String,
            callsite_pom: DependencyFile,
            updated_value: String
          ).returns(T::Array[DependencyFile])
        end
        def update_pomfiles_for_property_change(property_name:, callsite_pom:, updated_value:)
          declaration_details = property_value_finder.property_details(
            property_name: property_name,
            callsite_pom: callsite_pom
          )
          node = declaration_details&.fetch(:node)
          filename = declaration_details&.fetch(:file)

          file_to_update = dependency_files.find { |f| f.name == filename }

          # Check if this is a maven.config file
          if filename&.end_with?("maven.config")
            updated_content = update_maven_config_property(
              T.must(file_to_update),
              property_name,
              updated_value
            )
          else
            property_re = %r{<#{Regexp.quote(node.name)}>
              \s*#{Regexp.quote(node.content)}\s*
              </#{Regexp.quote(node.name)}>}xm
            property_text = node.to_s
            if file_to_update&.content&.match?(property_re)
              updated_content = file_to_update&.content&.sub(
                property_re,
                "<#{node.name}>#{updated_value}</#{node.name}>"
              )
            elsif file_to_update&.content&.include? property_text
              node.content = updated_value
              updated_content = file_to_update&.content&.sub(
                property_text,
                node.to_s
              )
            end
          end

          updated_pomfiles = dependency_files.dup
          updated_pomfiles[T.must(updated_pomfiles.index(file_to_update))] =
            update_file(file: T.must(file_to_update), content: T.must(updated_content))

          updated_pomfiles
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/AbcSize

        private

        sig { returns T::Array[Dependabot::DependencyFile] }
        attr_reader :dependency_files

        sig { returns Maven::FileParser::PropertyValueFinder }
        def property_value_finder
          @property_value_finder ||= T.let(
            Maven::FileParser::PropertyValueFinder.new(dependency_files: dependency_files),
            T.nilable(Dependabot::Maven::FileParser::PropertyValueFinder)
          )
        end

        sig { params(file: DependencyFile, content: String).returns(DependencyFile) }
        def update_file(file:, content:)
          updated_file = file.dup
          updated_file.content = content
          updated_file
        end

        sig { params(file: DependencyFile, property_name: String, updated_value: String).returns(String) }
        def update_maven_config_property(file, property_name, updated_value)
          property_regex = /^-D#{Regexp.escape(property_name)}=.+$/
          updated_lines = T.must(file.content).lines.map do |line|
            if property_regex.match?(line)
              line_ending = line.end_with?("\r\n") ? "\r\n" : "\n"
              "-D#{property_name}=#{updated_value}#{line_ending}"
            else
              line
            end
          end
          updated_lines.join
        end
      end
    end
  end
end
