# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/pub/helpers"

module Dependabot
  module Pub
    class FileUpdater < Dependabot::FileUpdaters::Base
      include Dependabot::Pub::Helpers

      def self.updated_files_regex
        [
          /^pubspec\.yaml$/,
          /^pubspec\.lock$/
        ]
      end

      def updated_dependency_files
        dependency_services_apply(@dependencies)
      end

      private

      def check_required_files
        raise "No pubspec.yaml!" unless get_original_file("pubspec.yaml")
      end
    end
  end
end

Dependabot::FileUpdaters.register("pub", Dependabot::Pub::FileUpdater)
