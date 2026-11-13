# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_updater"
require "dependabot/gradle/file_parser/property_value_finder"
require "dependabot/maven/shared/shared_property_value_updater"

module Dependabot
  module Gradle
    class FileUpdater
      class PropertyValueUpdater < Dependabot::Maven::Shared::SharedPropertyValueUpdater
        extend T::Sig

        private

        sig { override.returns(Gradle::FileParser::PropertyValueFinder) }
        def property_value_finder
          @property_value_finder ||= T.let(
            Gradle::FileParser::PropertyValueFinder.new(dependency_files: dependency_files),
            T.nilable(Gradle::FileParser::PropertyValueFinder)
          )
        end
      end
    end
  end
end
