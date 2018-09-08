# frozen_string_literal: true

require "dependabot/file_updaters/elm/elm_package"

module Dependabot
  module FileUpdaters
    module Elm
      class ElmPackage
        class ElmJsonUpdater
          def initialize(elm_json_file:, dependencies:)
            @elm_json_file = elm_json_file
            @dependencies = dependencies
          end

          def updated_content
            # TODO: Write me!
          end

          private

          attr_reader :elm_json_file, :dependencies

          def requirement_changed?(file, dependency)
            changed_requirements =
              dependency.requirements - dependency.previous_requirements

            changed_requirements.any? { |f| f[:file] == file.name }
          end
        end
      end
    end
  end
end
