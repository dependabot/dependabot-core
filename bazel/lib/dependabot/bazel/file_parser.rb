# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

module Dependabot
  module Bazel
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        # TODO: Implement parsing logic to extract dependencies from manifest files
        # Return an array of Dependency objects
        []
      end

      private

      sig { override.void }
      def check_required_files
        # TODO: Verify that all required files are present
        # Example:
        # return if get_original_file("manifest.json")
        # raise "No manifest.json file found!"
      end
    end
  end
end

Dependabot::FileParsers.register("bazel", Dependabot::Bazel::FileParser)
