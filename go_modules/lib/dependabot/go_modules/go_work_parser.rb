# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/experiments"

module Dependabot
  module GoModules
    class GoWorkParser
      extend T::Sig

      # Parses the `use` directives from go.work content.
      # Returns an array of module paths with `./` prefix (and, with the experiment, surrounding quotes) stripped.
      # `"."` is included when the root module is listed.
      # Result is deduped but not sorted, filtered, or re-prefixed.
      sig { params(content: String).returns(T::Array[String]) }
      def self.use_paths(content)
        return legacy_use_paths(content) unless Dependabot::Experiments.enabled?(:enable_go_work_version_sync)

        paths = T.let([], T::Array[String])

        # Multi-line use block: use (\n  ./path\n  ...\n)
        content.scan(/^use\s+\(([^)]+)\)/m).each do |block_match|
          T.must(block_match[0]).each_line do |line|
            path = normalize_path(line.split("//").first || "")
            next if path.empty?

            paths << path
          end
        end

        # Single-line use directive: use ., use ./path, use path or use "./path"
        content.scan(/^use\s+(?!\()("[^"]*"|[^\s"]+)/).each do |match|
          path = normalize_path(T.must(match[0]))
          paths << path unless path.empty?
        end

        paths.uniq
      end

      # Behaviour before the enable_go_work_version_sync experiment: only `use ./path` is recognised
      # on single lines and quotes are kept on block entries.
      sig { params(content: String).returns(T::Array[String]) }
      def self.legacy_use_paths(content)
        paths = T.let([], T::Array[String])

        content.scan(/^use\s+\(([^)]+)\)/m).each do |block_match|
          T.must(block_match[0]).each_line do |line|
            path = line.split("//").first&.strip || ""
            next if path.empty?

            paths << path.sub(%r{^\./}, "")
          end
        end

        content.scan(/^use\s+(?!\()(\.[^\s]*)/m).each do |match|
          paths << T.must(match[0]).sub(%r{^\./}, "")
        end

        paths.uniq
      end
      private_class_method :legacy_use_paths

      sig { params(raw_path: String).returns(String) }
      def self.normalize_path(raw_path)
        raw_path.strip.delete_prefix('"').delete_suffix('"').sub(%r{^\./}, "")
      end
      private_class_method :normalize_path
    end
  end
end
