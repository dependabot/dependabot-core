# typed: strong
# frozen_string_literal: true

module Dependabot
  module Python
    class PipCompileFileMatcher
      extend T::Sig

      NON_SOURCE_FILE_OPTION = /\A(?:-[cb]|--(?:build-)?constraints?|--overrides?)\z/

      sig { params(requirements_in_files: T::Array[DependencyFile]).void }
      def initialize(requirements_in_files)
        @requirements_in_files = requirements_in_files
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def lockfile_for_pip_compile_file?(file)
        return false unless requirements_in_files.any?

        name = file.name
        return false unless name.end_with?(".txt")

        return true if file.content&.match?(output_file_regex(name))

        !!manifest_for_lockfile_name(name)
      end

      # Returns nil when neither the name nor the compile command ties the output to an `.in`, as it may have been
      # compiled from another manifest such as `pyproject.toml`.
      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::DependencyFile)) }
      def manifest_for_pip_compile_lockfile(file)
        return nil unless lockfile_for_pip_compile_file?(file)

        manifest_for_lockfile_name(file.name) || manifest_named_in_header(file)
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      attr_reader :requirements_in_files

      # pip-compile and uv record their command in the output's header, which names the source manifest.
      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::DependencyFile)) }
      def manifest_named_in_header(file)
        sources = compile_command_sources(file)

        requirements_in_files.find do |f|
          sources.any? { |source| source == f.name || source.end_with?("/#{f.name}") }
        end
      end

      # Constraint and override files are inputs too, so they're excluded to leave only the sources.
      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def compile_command_sources(file)
        header = file.content.to_s.lines.take_while { |line| line.start_with?("#") }
        tokens = header.flat_map { |line| line.delete_prefix("#").split }

        tokens.each_with_index.filter_map do |token, i|
          next if token.start_with?("-")
          next if i.positive? && tokens.fetch(i - 1).match?(NON_SOURCE_FILE_OPTION)

          token
        end
      end

      sig { params(filename: T.any(String, Symbol)).returns(String) }
      def output_file_regex(filename)
        "--output-file[=\s]+#{Regexp.escape(filename)}(?:\s|$)"
      end

      sig { params(lockfile_name: String).returns(T.nilable(Dependabot::DependencyFile)) }
      def manifest_for_lockfile_name(lockfile_name)
        basename = lockfile_name.gsub(/\.txt$/, "")
        requirements_in_files.find { |f| f.name == basename + ".in" }
      end
    end
  end
end
