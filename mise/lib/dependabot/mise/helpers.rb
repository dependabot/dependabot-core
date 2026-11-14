# typed: strong
# frozen_string_literal: true

require "fileutils"

module Dependabot
  module Mise
    module Helpers
      extend T::Sig

      private

      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
      def write_manifest_files(dependency_files)
        dependency_files.each do |file|
          FileUtils.mkdir_p(File.dirname(file.name))
          File.write(file.name, file.content)
        end
      end
    end
  end
end
