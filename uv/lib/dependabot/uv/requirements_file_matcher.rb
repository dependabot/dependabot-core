# typed: strong
# frozen_string_literal: true

require "dependabot/dependency_file"

module Dependabot
  module Uv
    class RequiremenstFileMatcher
      extend T::Sig

      sig { params(requirements_in_files: T::Array[DependencyFile]).void }
      def initialize(requirements_in_files)
        @requirements_in_files = requirements_in_files
      end

      sig { params(file: DependencyFile).returns(T::Boolean) }
      def compiled_file?(file)
        return false unless requirements_in_files.any?

        name = file.name
        return false unless name.end_with?(".txt")

        return true if file.content&.match?(output_file_regex(name))

        basename = name.gsub(/\.txt$/, "")
        requirements_in_files.any? { |f| f.name == basename + ".in" }
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      attr_reader :requirements_in_files

      sig { params(filename: T.any(String, Symbol)).returns(String) }
      def output_file_regex(filename)
        "--output-file[=\s]+#{Regexp.escape(filename)}(?:\s|$)"
      end
    end
  end
end
