# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/manifest_sets/catalog"

module Dependabot
  # Static description of which repository files form a manifest set, shared with downstream
  # dependency-graph consumers as data (see manifest_sets/README.md).
  module ManifestSets
    extend T::Sig

    DATA_DIR = T.let(File.expand_path("manifest_sets", __dir__).freeze, String)
    CATALOG_PATH = T.let(File.join(DATA_DIR, "catalog.json").freeze, String)
    SCHEMA_PATH = T.let(File.join(DATA_DIR, "catalog.schema.json").freeze, String)
    FIXTURES_DIR = T.let(File.join(DATA_DIR, "fixtures").freeze, String)

    @catalog = T.let(nil, T.nilable(Catalog))

    # The catalog bundled with this gem, validated once per process.
    sig { returns(Catalog) }
    def self.catalog
      @catalog ||= Catalog.parse(File.read(CATALOG_PATH, encoding: "UTF-8"))
    end
  end
end
