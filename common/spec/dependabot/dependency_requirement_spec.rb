# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_requirement"

RSpec.describe Dependabot::DependencyRequirement do
  let(:requirement_hash) do
    {
      requirement: ">= 1.0, < 2.0",
      file: "Gemfile",
      groups: [:default],
      source: { type: "rubygems", url: "https://rubygems.org" },
      metadata: { property_name: "rails.version" }
    }
  end

  describe ".create" do
    it "symbolises string keys" do
      requirement = described_class.create(
        "requirement" => ">= 1.0",
        "file" => "Gemfile",
        "groups" => [],
        "source" => nil
      )

      expect(requirement).to eq(
        requirement: ">= 1.0",
        file: "Gemfile",
        groups: [],
        source: nil
      )
    end

    it "returns a new instance when given a DependencyRequirement" do
      original = described_class.create(requirement_hash)
      copy = described_class.create(original)

      expect(copy).to eq(original)
      expect(copy).not_to equal(original)
    end

    it "preserves unknown keys and values" do
      requirement = described_class.create(requirement_hash.merge(custom: { count: 1 }))

      expect(requirement[:custom]).to eq(count: 1)
    end
  end

  describe "typed readers" do
    subject(:requirement) { described_class.create(requirement_hash) }

    it "exposes the well-known keys" do
      expect(requirement.requirement).to eq(">= 1.0, < 2.0")
      expect(requirement.file).to eq("Gemfile")
      expect(requirement.groups).to eq([:default])
      expect(requirement.source).to eq(type: "rubygems", url: "https://rubygems.org")
      expect(requirement.metadata).to eq(property_name: "rails.version")
    end

    it "returns nil for absent optional keys" do
      minimal = described_class.create(requirement: nil, file: "Gemfile", groups: [], source: nil)

      expect(minimal.requirement).to be_nil
      expect(minimal.source).to be_nil
      expect(minimal.metadata).to be_nil
    end

    it "returns string source names" do
      req = described_class.create(requirement: ">= 1.0", file: "pyproject.toml", groups: [], source: "internal")

      expect(req.source).to eq("internal")
    end

    it "returns nil groups without raising when the entry has groups: nil" do
      req = described_class.create(requirement: ">= 1.0", file: "Gemfile", groups: nil, source: nil)

      expect(req.groups).to be_nil
    end

    it "returns the unfixable requirement sentinel" do
      req = described_class.create(requirement: :unfixable, file: "Gemfile", groups: [], source: nil)

      expect(req.requirement).to eq(:unfixable)
    end

    it "rejects malformed scalar fields" do
      malformed_requirement = described_class.create(requirement_hash.merge(requirement: 1))
      malformed_requirement_symbol = described_class.create(requirement_hash.merge(requirement: :unknown))
      malformed_file = described_class.create(requirement_hash.merge(file: false))

      expect { malformed_requirement.requirement }
        .to raise_error(TypeError, "requirement must be a string, :unfixable, or nil")
      expect { malformed_requirement_symbol.requirement }
        .to raise_error(TypeError, "requirement must be a string, :unfixable, or nil")
      expect { malformed_file.file }
        .to raise_error(TypeError, "file must be a string or nil")
    end

    it "rejects malformed groups" do
      malformed_container = described_class.create(requirement_hash.merge(groups: "default"))
      malformed_entry = described_class.create(requirement_hash.merge(groups: [:default, 1]))

      expect { malformed_container.groups }
        .to raise_error(TypeError, "groups must be an array of strings or symbols, or nil")
      expect { malformed_entry.groups }
        .to raise_error(TypeError, "groups must be an array of strings or symbols, or nil")
    end

    it "rejects malformed source and metadata hashes" do
      malformed_source = described_class.create(requirement_hash.merge(source: []))
      malformed_source_key = described_class.create(requirement_hash.merge(source: { 1 => "rubygems" }))
      malformed_metadata = described_class.create(requirement_hash.merge(metadata: "rails.version"))

      expect { malformed_source.source }
        .to raise_error(TypeError, "source must be a string or hash with string or symbol keys, or nil")
      expect { malformed_source_key.source }
        .to raise_error(TypeError, "source must be a string or hash with string or symbol keys, or nil")
      expect { malformed_metadata.metadata }
        .to raise_error(TypeError, "metadata must be a hash with string or symbol keys, or nil")
    end

    it "returns the mutable source and metadata hashes" do
      requirement.source[:mirror] = "https://example.com"
      requirement.metadata[:property_name] = "rack.version"

      expect(requirement.dig(:source, :mirror)).to eq("https://example.com")
      expect(requirement.dig(:metadata, :property_name)).to eq("rack.version")
    end
  end

  describe "hash compatibility" do
    subject(:requirement) { described_class.create(requirement_hash) }

    it "supports hash-style access" do
      expect(requirement[:file]).to eq("Gemfile")
      expect(requirement.fetch(:requirement)).to eq(">= 1.0, < 2.0")
      expect(requirement.dig(:source, :type)).to eq("rubygems")
    end

    it "compares equal to a plain hash with the same content" do
      expect(requirement).to eq(requirement_hash)
      expect(requirement_hash).to eq(requirement)
      expect(requirement.eql?(requirement_hash)).to be(true)
      expect(requirement.hash).to eq(requirement_hash.hash)
    end

    it "interoperates with plain hashes in Array and Set operations" do
      expect([requirement] - [requirement_hash]).to be_empty
      expect([requirement_hash, requirement].uniq.length).to eq(1)
      expect(Set.new([requirement_hash])).to include(requirement)
    end

    it "preserves the class through merge" do
      merged = requirement.merge(requirement: ">= 2.0")

      expect(merged).to be_a(described_class)
      expect(merged.requirement).to eq(">= 2.0")
      expect(requirement.requirement).to eq(">= 1.0, < 2.0")
    end

    it "serialises to JSON like a plain hash" do
      expect(JSON.parse(requirement.to_json)).to eq(JSON.parse(requirement_hash.to_json))
    end
  end
end
