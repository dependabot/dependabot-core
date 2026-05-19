# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_file"

module Dependabot
  module Maven
    module Shared
      # Shared base for text-based property value updaters (Gradle, SBT).
      # Subclasses must override `property_value_finder` to return the
      # ecosystem-specific PropertyValueFinder instance.
      #
      # Maven's PropertyValueUpdater is XML-based and does not share this class.
      class SharedPropertyValueUpdater
        extend T::Sig
        extend T::Helpers

        abstract!

        sig { params(dependency_files: T::Array[DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = T.let(dependency_files, T::Array[DependencyFile])
        end

        sig do
          params(
            property_name: String,
            callsite_buildfile: DependencyFile,
            previous_value: String,
            updated_value: String
          ).returns(T::Array[DependencyFile])
        end
        def update_files_for_property_change(
          property_name:,
          callsite_buildfile:,
          previous_value:,
          updated_value:
        )
          declaration_details = property_value_finder.property_details(
            property_name: property_name,
            callsite_buildfile: callsite_buildfile
          )
          raise "Property '#{property_name}' not found" unless declaration_details

          declaration_string = T.let(declaration_details.fetch(:declaration_string), String)
          filename = T.let(declaration_details.fetch(:file), String)

          file_to_update = T.must(dependency_files.find { |f| f.name == filename })
          updated_content = T.must(file_to_update.content).sub(
            declaration_string,
            declaration_string.sub(
              previous_value_regex(previous_value),
              updated_value
            )
          )

          updated_files = dependency_files.dup
          updated_files[T.must(updated_files.index(file_to_update))] =
            update_file(file: file_to_update, content: updated_content)

          updated_files
        end

        private

        sig { returns(T::Array[DependencyFile]) }
        attr_reader :dependency_files

        sig { abstract.returns(T.untyped) }
        def property_value_finder; end

        sig { params(previous_value: String).returns(Regexp) }
        def previous_value_regex(previous_value)
          /(?<=['"])#{Regexp.quote(previous_value)}(?=['"])/
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
