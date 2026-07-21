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

    it "rejects missing required keys" do
      expect do
        described_class.create(requirement: ">= 1.0", file: "Gemfile", groups: [])
      end.to raise_error(ArgumentError, /required keys/)
    end

    it "rejects unknown keys" do
      expect do
        described_class.create(requirement_hash.merge(unknown: "value"))
      end.to raise_error(ArgumentError, /unknown keys/)
    end

    it "rejects blank requirement strings" do
      expect do
        described_class.create(requirement_hash.merge(requirement: ""))
      end.to raise_error(ArgumentError, "blank strings must not be provided as requirements")
    end

    it "rejects malformed known fields" do
      expect do
        described_class.create(requirement_hash.merge(file: 1))
      end.to raise_error(TypeError, "file must be a string or nil")

      expect do
        described_class.create(requirement_hash.merge(groups: ["default", 1]))
      end.to raise_error(TypeError, "groups must be an array of strings or symbols, or nil")

      expect do
        described_class.create(requirement_hash.merge(source: "rubygems"))
      end.to raise_error(TypeError, "source must be a hash or nil")

      expect do
        described_class.create(requirement_hash.merge(metadata: "rails.version"))
      end.to raise_error(TypeError, "metadata must be a hash or nil")
    end

    it "accepts the unfixable requirement sentinel" do
      requirement = described_class.create(requirement_hash.merge(requirement: :unfixable))

      expect(requirement).to be_unfixable
      expect(requirement.requirement).to be_nil
      expect(requirement.to_h[:requirement]).to eq(:unfixable)
    end

    it "rejects other requirement symbols" do
      expect do
        described_class.create(requirement_hash.merge(requirement: :unknown))
      end.to raise_error(TypeError, "requirement must be a string, :unfixable, or nil")
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

    it "returns nil groups without raising when the entry has groups: nil" do
      req = described_class.create(requirement: ">= 1.0", file: "Gemfile", groups: nil, source: nil)

      expect(req.groups).to be_nil
    end

    it "preserves mixed string and symbol groups" do
      req = described_class.create(
        requirement: ">= 1.0",
        file: "Gemfile",
        groups: ["development", :default],
        source: nil
      )

      expect(req.groups).to eq(["development", :default])
    end
  end

  describe "typed copies" do
    subject(:requirement) { described_class.create(requirement_hash) }

    it "replaces the requirement" do
      updated = requirement.with_requirement(">= 2.0")

      expect(updated.requirement).to eq(">= 2.0")
      expect(requirement.requirement).to eq(">= 1.0, < 2.0")
    end

    it "replaces source and metadata" do
      updated = requirement
                .with_source(type: "git", url: "https://github.com/dependabot/dependabot-core")
                .with_metadata(property_name: "dependabot.version")

      expect(updated.source).to eq(
        type: "git",
        url: "https://github.com/dependabot/dependabot-core"
      )
      expect(updated.metadata).to eq(property_name: "dependabot.version")
    end

    it "preserves whether metadata was absent" do
      without_metadata = described_class.create(
        requirement: ">= 1.0",
        file: "Gemfile",
        groups: [],
        source: nil
      )

      expect(without_metadata.to_h).not_to have_key(:metadata)
      expect(without_metadata.with_requirement(">= 2.0").to_h).not_to have_key(:metadata)
      expect(without_metadata.with_metadata(nil).to_h).to have_key(:metadata)
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
