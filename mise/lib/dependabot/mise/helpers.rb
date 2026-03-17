# typed: strong
# frozen_string_literal: true

module Dependabot
  module Mise
    module Helpers
      extend T::Sig

      private

      # Writes all fetched dependency files to the current working directory.
      # Used inside SharedHelpers.in_a_temporary_directory blocks before
      # shelling out to mise CLI commands.
      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
      def write_manifest_files(dependency_files)
        dependency_files.each { |f| File.write(f.name, f.content) }
      end
    end
  end
end
