# typed: strict
# frozen_string_literal: true

require "dependabot/bazel/file_fetcher"
require "dependabot/bazel/file_fetcher/path_converter"
require "sorbet-runtime"

module Dependabot
  module Bazel
    class FileFetcher < Dependabot::FileFetchers::Base
      # Extracts file and directory paths referenced in MODULE.bazel files.
      # Handles attributes like lock_file, requirements_lock, patches, and local_path_override.
      class ModulePathExtractor
        extend T::Sig

        sig { params(module_file: DependencyFile).void }
        def initialize(module_file:)
          @module_file = module_file
        end

        sig { returns([T::Array[String], T::Array[String]]) }
        def extract_paths
          content = T.must(@module_file.content)
          file_paths = extract_file_attribute_paths(content)
          directory_paths = extract_directory_paths(content)
          [file_paths.uniq, directory_paths.uniq]
        end

        private

        sig { returns(DependencyFile) }
        attr_reader :module_file

        # Extracts file paths from lock_file, requirements_lock, and patches attributes.
        sig { params(content: String).returns(T::Array[String]) }
        def extract_file_attribute_paths(content)
          (
            extract_lock_file_paths(content) +
            extract_requirements_lock_paths(content) +
            extract_patches_paths(content)
          ).compact
        end

        sig { params(content: String).returns(T::Array[String]) }
        def extract_lock_file_paths(content)
          content.scan(/lock_file\s*=\s*"([^"]+)"/).map { |match| PathConverter.label_to_path(T.must(match[0])) }
        end

        sig { params(content: String).returns(T::Array[String]) }
        def extract_requirements_lock_paths(content)
          content.scan(/requirements_lock\s*=\s*"([^"]+)"/).map do |match|
            PathConverter.label_to_path(T.must(match[0]))
          end
        end

        sig { params(content: String).returns(T::Array[String]) }
        def extract_patches_paths(content)
          patches = []
          content.scan(/patches\s*=\s*\[([^\]]+)\]/) do |match|
            match[0].scan(/"([^"]+)"/) { |file| patches << PathConverter.label_to_path(file[0]) }
          end
          content.scan(/patches\s*=\s*"([^"]+)"/) do |match|
            patches << PathConverter.label_to_path(match[0])
          end
          patches
        end

        # Extracts directory paths from local_path_override attributes.
        sig { params(content: String).returns(T::Array[String]) }
        def extract_directory_paths(content)
          extract_local_path_override_paths(content)
            .reject { |path| PathConverter.should_filter_path?(path) }
            .map { |path| PathConverter.normalize_path(path) }
        end

        sig { params(content: String).returns(T::Array[String]) }
        def extract_local_path_override_paths(content)
          content.scan(/local_path_override\s*\([^)]*path\s*=\s*"([^"]+)"[^)]*\)/m).flatten
        end
      end
    end
  end
end
