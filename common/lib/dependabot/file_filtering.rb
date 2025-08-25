# typed: strict
# frozen_string_literal: true

module Dependabot
  module FileFiltering
    extend T::Sig

    # Returns true if the given path matches any of the exclude patterns
    sig { params(path: String, exclude_patterns: T.nilable(T::Array[String])).returns(T::Boolean) }
    def self.exclude_path?(path, exclude_patterns) # rubocop:disable Metrics/PerceivedComplexity
      return false if exclude_patterns.nil? || exclude_patterns.empty?

      exclude_patterns.any? do |pattern|
        normalized_pattern = pattern.chomp("/")
        normalized_path = path.chomp("/")

        # case 1: exact match
        exclude_exact = path == pattern || normalized_path == normalized_pattern

        # case 2: Directory prefix matching: check if path is inside an excluded directory
        exclude_deeper = path.start_with?("#{pattern}#{File::SEPARATOR}",
                                          "#{normalized_pattern}#{File::SEPARATOR}")

        # case 3: Explicit recursive (patterns that end with /**)
        exclude_recursive = false
        if pattern.end_with?("/**")
          base_pattern = pattern[0...-3]
          exclude_recursive = path == base_pattern ||
                              path.start_with?("#{base_pattern}/") ||
                              path.start_with?("#{base_pattern}#{File::SEPARATOR}")
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
          File.fnmatch?(pattern, path, flag)
        end

        result = exclude_exact || exclude_deeper || exclude_recursive || exclude_fnmatch_paths
        result
      end
    end
  end
end
