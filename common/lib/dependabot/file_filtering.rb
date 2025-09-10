# typed: strong
# frozen_string_literal: true

module Dependabot
  module FileFiltering
    extend T::Sig

    # Returns true if the given path matches any of the exclude patterns
    sig { params(path: String, exclude_patterns: T.nilable(T::Array[String])).returns(T::Boolean) }
    def self.exclude_path?(path, exclude_patterns) # rubocop:disable Metrics/PerceivedComplexity,Metrics/CyclomaticComplexity
      return false if exclude_patterns.nil? || exclude_patterns.empty?

      # Normalize the path by removing leading slashes and resolving relative paths
      normalized_path = normalize_path(path)

      exclude_patterns.any? do |pattern|
        normalized_pattern = normalize_path(pattern.chomp("/"))

        # case 1: exact match
        exclude_exact = normalized_path == pattern || normalized_path == normalized_pattern

        # case 2: Directory prefix matching: check if path is inside an excluded directory
        exclude_deeper = normalized_path.start_with?("#{pattern}#{File::SEPARATOR}",
                                                     "#{normalized_pattern}#{File::SEPARATOR}")

        # case 3: Explicit recursive (patterns that end with /**)
        exclude_recursive = false
        if pattern.end_with?("/**")
          base_pattern_str = pattern[0...-3]
          base_pattern = normalize_path(base_pattern_str) if base_pattern_str && !base_pattern_str.empty?
          exclude_recursive = !base_pattern.nil? && !base_pattern.empty? && (
            normalized_path == base_pattern ||
            normalized_path.start_with?("#{base_pattern}/") ||
            normalized_path.start_with?("#{base_pattern}#{File::SEPARATOR}")
          )
        end

        # case 4: Glob pattern matching with enhanced flags
        # Use multiple fnmatch attempts with different flag combinations
        fnmatch_flags = [
          File::FNM_EXTGLOB,
          File::FNM_EXTGLOB | File::FNM_PATHNAME,
          File::FNM_EXTGLOB | File::FNM_PATHNAME | File::FNM_DOTMATCH,
          File::FNM_PATHNAME
        ]
        exclude_fnmatch_paths = fnmatch_flags.any? do |flag|
          File.fnmatch?(pattern, normalized_path, flag) || File.fnmatch?(normalized_pattern, normalized_path, flag)
        end

        result = exclude_exact || exclude_deeper || exclude_recursive || exclude_fnmatch_paths
        result
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
