# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/sbt/file_updater"
require "dependabot/sbt/file_parser/property_value_finder"
require "dependabot/maven/shared/shared_property_value_updater"

module Dependabot
  module Sbt
    class FileUpdater < Dependabot::FileUpdaters::Base
      class PropertyValueUpdater < Dependabot::Maven::Shared::SharedPropertyValueUpdater
        extend T::Sig

        private

        sig { override.returns(Sbt::FileParser::PropertyValueFinder) }
        def property_value_finder
          @property_value_finder ||= T.let(
            Sbt::FileParser::PropertyValueFinder.new(dependency_files: dependency_files),
            T.nilable(Sbt::FileParser::PropertyValueFinder)
          )
        end
      end
    end
  end
end
