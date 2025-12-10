# typed: strict
# frozen_string_literal: true

require "dependabot/bazel/file_fetcher"
require "sorbet-runtime"

module Dependabot
  module Bazel
    class FileFetcher < Dependabot::FileFetchers::Base
      # Converts Bazel label syntax to filesystem paths
      class PathConverter
        extend T::Sig

        sig { params(label: String, context_dir: T.nilable(String)).returns(String) }
        def self.label_to_path(label, context_dir: nil)
          path = strip_external_repo_prefix(label)
          return resolve_relative_path(path, context_dir) if relative_path?(path)

          convert_absolute_label_to_path(path)
        end

        sig { params(path: String).returns(T::Boolean) }
        def self.should_filter_path?(path)
          absolute_path_or_url?(path)
        end

        sig { params(path: String).returns(String) }
        def self.normalize_path(path)
          remove_leading_dot_slash(path)
        end

        sig { params(label: String).returns(String) }
        private_class_method def self.strip_external_repo_prefix(label)
          label.sub(%r{^@[^/]+//}, "")
        end

        sig { params(path: String).returns(T::Boolean) }
        private_class_method def self.relative_path?(path)
          path.start_with?(":")
        end

        sig { params(path: String, context_dir: T.nilable(String)).returns(String) }
        private_class_method def self.resolve_relative_path(path, context_dir)
          relative_file = path.sub(/^:/, "")
          return relative_file if context_dir.nil? || context_dir == "."

          "#{context_dir}/#{relative_file}"
        end

        sig { params(path: String).returns(String) }
        private_class_method def self.convert_absolute_label_to_path(path)
          path_with_slashes = replace_colon_separator_with_slash(path)
          remove_leading_slashes(path_with_slashes)
        end

        sig { params(path: String).returns(String) }
        private_class_method def self.replace_colon_separator_with_slash(path)
          path.tr(":", "/")
        end

        sig { params(path: String).returns(String) }
        private_class_method def self.remove_leading_slashes(path)
          path.sub(%r{^/+}, "")
        end

        sig { params(path: String).returns(T::Boolean) }
        private_class_method def self.absolute_path_or_url?(path)
          path.start_with?("http://", "https://", "/", "@")
        end

        sig { params(path: String).returns(String) }
        private_class_method def self.remove_leading_dot_slash(path)
          path.sub(%r{^\./}, "")
        end
      end
    end
  end
end
