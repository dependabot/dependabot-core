# typed: strict
# frozen_string_literal: true

require "dependabot/bazel/file_fetcher"
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
        #
        # @param content [String] the MODULE.bazel file content
        # @return [Array<String>] extracted file paths
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
          content.scan(/lock_file\s*=\s*"([^"]+)"/).map { |match| convert_label_to_path(T.must(match[0])) }
        end

        sig { params(content: String).returns(T::Array[String]) }
        def extract_requirements_lock_paths(content)
          content.scan(/requirements_lock\s*=\s*"([^"]+)"/).map { |match| convert_label_to_path(T.must(match[0])) }
        end

        sig { params(content: String).returns(T::Array[String]) }
        def extract_patches_paths(content)
          patches = []
          content.scan(/patches\s*=\s*\[([^\]]+)\]/) do |match|
            match[0].scan(/"([^"]+)"/) { |file| patches << convert_label_to_path(file[0]) }
          end
          content.scan(/patches\s*=\s*"([^"]+)"/) do |match|
            patches << convert_label_to_path(match[0])
          end
          patches
        end

        # Extracts directory paths from local_path_override attributes.
        #
        # @param content [String] the MODULE.bazel file content
        # @return [Array<String>] extracted directory paths
        sig { params(content: String).returns(T::Array[String]) }
        def extract_directory_paths(content)
          extract_local_path_override_paths(content)
            .reject { |path| absolute_or_url?(path) }
            .map { |path| normalize_relative_path(path) }
        end

        sig { params(content: String).returns(T::Array[String]) }
        def extract_local_path_override_paths(content)
          content.scan(/local_path_override\s*\([^)]*path\s*=\s*"([^"]+)"[^)]*\)/m).flatten
        end

        sig { params(path: String).returns(T::Boolean) }
        def absolute_or_url?(path)
          path.start_with?("http://", "https://", "/")
        end

        sig { params(path: String).returns(String) }
        def normalize_relative_path(path)
          path.sub(%r{^\./}, "")
        end

        # Converts Bazel label syntax to filesystem paths.
        # Bazel labels can reference external repos (@repo//) or local files (// or :).
        sig { params(label: String).returns(String) }
        def convert_label_to_path(label)
          label = label.sub(%r{^@[^/]+//}, "")
          label = label.tr(":", "/")
          label.sub(%r{^/+}, "")
        end
      end
    end
  end
end
