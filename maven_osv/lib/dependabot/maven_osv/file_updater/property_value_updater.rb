# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/maven_osv/file_updater"
require "dependabot/maven_osv/file_parser/property_value_finder"

module Dependabot
  module MavenOSV
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
        def update_pomfiles_for_property_change(property_name:, callsite_pom:,
                                                updated_value:)
          declaration_details = property_value_finder.property_details(
            property_name: property_name,
            callsite_pom: callsite_pom
          )
          node = declaration_details&.fetch(:node)
          filename = declaration_details&.fetch(:file)

          pom_to_update = dependency_files.find { |f| f.name == filename }
          property_re = %r{<#{Regexp.quote(node.name)}>
            \s*#{Regexp.quote(node.content)}\s*
            </#{Regexp.quote(node.name)}>}xm
          property_text = node.to_s
          if pom_to_update&.content&.match?(property_re)
            updated_content = pom_to_update&.content&.sub(
              property_re,
              "<#{node.name}>#{updated_value}</#{node.name}>"
            )
          elsif pom_to_update&.content&.include? property_text
            node.content = updated_value
            updated_content = pom_to_update&.content&.sub(
              property_text,
              node.to_s
            )
          end

          updated_pomfiles = dependency_files.dup
          updated_pomfiles[T.must(updated_pomfiles.index(pom_to_update))] =
            update_file(file: T.must(pom_to_update), content: T.must(updated_content))

          updated_pomfiles
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/AbcSize

        private

        sig { returns T::Array[Dependabot::DependencyFile] }
        attr_reader :dependency_files

        sig { returns MavenOSV::FileParser::PropertyValueFinder }
        def property_value_finder
          @property_value_finder ||= T.let(
            MavenOSV::FileParser::PropertyValueFinder.new(dependency_files: dependency_files),
            T.nilable(Dependabot::MavenOSV::FileParser::PropertyValueFinder)
          )
        end

        sig { params(file: DependencyFile, content: String).returns(DependencyFile) }
        def update_file(file:, content:)
          updated_file = file.dup
          updated_file.content = content
          updated_file
        end
      end
    end
  end
end
