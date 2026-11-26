# typed: strict
# frozen_string_literal: true

require "digest"
require "json"
require "sorbet-runtime"

module Dependabot
  module ManifestSets
    # A sha256 manifest of the published manifest-set data files, so a downstream consumer that vendors them at
    # a pinned commit can verify it copied exactly what this commit ships.
    module Digests
      extend T::Sig

      MANIFEST_NAME = "digests.json"
      SCHEMA_VERSION = 1
      PUBLISHED_GLOBS = ["*.json", "fixtures/**/*.json"].freeze

      # Published files relative to `data_dir`, sorted by bytes. The manifest never lists itself.
      sig { params(data_dir: String).returns(T::Array[String]) }
      def self.published_files(data_dir)
        PUBLISHED_GLOBS
          .flat_map { |glob| Dir.glob(glob, base: data_dir) }
          .reject { |path| path == MANIFEST_NAME }
          .uniq
          .sort_by(&:b)
      end

      sig { params(data_dir: String).returns(String) }
      def self.render(data_dir)
        files = published_files(data_dir).map do |path|
          { "path" => path, "sha256" => Digest::SHA256.file(File.join(data_dir, path)).hexdigest }
        end
        "#{JSON.pretty_generate({ 'schema_version' => SCHEMA_VERSION, 'algorithm' => 'sha256', 'files' => files })}\n"
      end

      sig { params(data_dir: String).returns(String) }
      def self.manifest_path(data_dir)
        File.join(data_dir, MANIFEST_NAME)
      end

      sig { params(data_dir: String).returns(T::Boolean) }
      def self.up_to_date?(data_dir)
        path = manifest_path(data_dir)
        File.exist?(path) && File.read(path) == render(data_dir)
      end

      sig { params(data_dir: String).void }
      def self.write(data_dir)
        File.write(manifest_path(data_dir), render(data_dir))
      end
    end
  end
end
