# typed: true
# frozen_string_literal: true

module Dependabot
  module Python
    class PipCompileFileMatcher
      def initialize(requirements_in_files)
        @requirements_in_files = requirements_in_files
      end

      def lockfile_for_pip_compile_file?(file)
        return false unless requirements_in_files.any?

        name = file.name
        return false unless name.end_with?(".txt")

        return true if file.content.match?(output_file_regex(name))

        basename = name.gsub(/\.txt$/, "")
        requirements_in_files.any? { |f| f.name == basename + ".in" }
      end

      private

      attr_reader :requirements_in_files

      def output_file_regex(filename)
        "--output-file[=\s]+#{Regexp.escape(filename)}(?:\s|$)"
      end
    end
  end
end
