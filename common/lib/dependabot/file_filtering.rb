# typed: strong
# frozen_string_literal: true

module Dependabot
  module FileFiltering
    extend T::Sig

    # Returns true if the given path matches any of the exclude patterns
    sig { params(path: String, exclude_patterns: T.nilable(T::Array[String])).returns(T::Boolean) }
    def self.exclude_path?(path, exclude_patterns)
      return false if exclude_patterns.nil? || exclude_patterns.empty?

      # Normalize the path by removing leading slashes and resolving relative paths
      normalized_path = normalize_path(path)

      exclude_patterns.any? do |pattern|
        normalized_pattern = normalize_path(pattern.chomp("/"))

        exact_or_directory_match?(normalized_path, pattern, normalized_pattern) ||
          recursive_match?(normalized_path, pattern) ||
          glob_match?(normalized_path, pattern, normalized_pattern)
      end
    end

    # Check for exact path matches or directory prefix matches
    sig { params(normalized_path: String, pattern: String, normalized_pattern: String).returns(T::Boolean) }
    def self.exact_or_directory_match?(normalized_path, pattern, normalized_pattern)
      # Exact match
      return true if normalized_path == pattern || normalized_path == normalized_pattern

      # Directory prefix match: check if path is inside an excluded directory
      normalized_path.start_with?("#{pattern}#{File::SEPARATOR}",
                                  "#{normalized_pattern}#{File::SEPARATOR}")
    end

    # Check for recursive pattern matches (patterns ending with /**)
    sig { params(normalized_path: String, pattern: String).returns(T::Boolean) }
    def self.recursive_match?(normalized_path, pattern)
      return false unless pattern.end_with?("/**")

      base_pattern_str = pattern[0...-3]
      return false if base_pattern_str.nil? || base_pattern_str.empty?

      base_pattern = normalize_path(base_pattern_str)
      return false if base_pattern.empty?

      normalized_path == base_pattern ||
        normalized_path.start_with?("#{base_pattern}/") ||
        normalized_path.start_with?("#{base_pattern}#{File::SEPARATOR}")
    end

    # Check for glob pattern matches with various fnmatch flags
    sig { params(normalized_path: String, pattern: String, normalized_pattern: String).returns(T::Boolean) }
    def self.glob_match?(normalized_path, pattern, normalized_pattern)
      fnmatch_flags = [
        File::FNM_EXTGLOB,
        File::FNM_EXTGLOB | File::FNM_PATHNAME,
        File::FNM_EXTGLOB | File::FNM_PATHNAME | File::FNM_DOTMATCH,
        File::FNM_PATHNAME
      ]

      fnmatch_flags.any? do |flag|
        File.fnmatch?(pattern, normalized_path, flag) || File.fnmatch?(normalized_pattern, normalized_path, flag)
      end
    end

    # Normalize a file path for consistent comparison
    # - Removes leading slashes
    # - Resolves relative path components (., ..)
    sig { params(path: String).returns(String) }
    def self.normalize_path(path)
      return path if path.empty?

      pathname = Pathname.new(path)
      normalized = pathname.cleanpath.to_s

      # Remove leading slash for relative comparison
      normalized = normalized.sub(%r{^/+}, "")
      normalized
    end

    # Helper method to check if a file path should be excluded
    sig do
      params(path: String,
             context: String,
             exclude_paths: T.nilable(T::Array[String])).returns(T::Boolean)
    end
    def self.should_exclude_path?(path, context, exclude_paths)
      return false unless Dependabot::Experiments.enabled?(:enable_exclude_paths_subdirectory_manifest_files)

      return false if exclude_paths.nil? || exclude_paths.empty?

      should_exclude = exclude_path?(path, exclude_paths)

      if should_exclude
        Dependabot.logger.warn(
          "Skipping excluded #{context} '#{path}'. " \
          "This file is excluded by exclude_paths configuration: #{exclude_paths}"
        )
      end

      should_exclude
    end
  end
end
