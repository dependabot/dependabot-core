# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/pub/helpers"
require "sorbet-runtime"

module Dependabot
  module Pub
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      include Dependabot::Pub::Helpers

      sig { override.params(_: T::Boolean).returns(T::Array[Regexp]) }
      def self.updated_files_regex(_ = false)
        [
          /^pubspec\.yaml$/,
          /^pubspec\.lock$/
        ]
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def updated_dependency_files
        dependency_services_apply(@dependencies)
      end

      private

      sig { override.void }
      def check_required_files
        raise "No pubspec.yaml!" unless get_original_file("pubspec.yaml")
      end
    end
  end
end

Dependabot::FileUpdaters.register("pub", Dependabot::Pub::FileUpdater)
