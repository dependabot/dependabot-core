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

  describe ".from_hash" do
    it "symbolises string keys" do
      requirement = described_class.from_hash(
        "requirement" => ">= 1.0",
        "file" => "Gemfile",
        "groups" => [],
        "source" => nil
      )

      expect(requirement.to_h).to eq(
        requirement: ">= 1.0",
        file: "Gemfile",
        groups: [],
        source: nil
      )
    end

    it "rejects missing required keys" do
      expect do
        described_class.from_hash(requirement: ">= 1.0", file: "Gemfile", groups: [])
      end.to raise_error(ArgumentError, /required keys/)
    end

    it "rejects unknown keys" do
      expect do
        described_class.from_hash(requirement_hash.merge(unknown: "value"))
      end.to raise_error(ArgumentError, /unknown keys/)
    end

    it "rejects blank requirement strings" do
      expect do
        described_class.from_hash(requirement_hash.merge(requirement: ""))
      end.to raise_error(ArgumentError, "blank strings must not be provided as requirements")
    end

    it "rejects malformed known fields" do
      expect do
        described_class.from_hash(requirement_hash.merge(file: 1))
      end.to raise_error(TypeError, "file must be a string or nil")

      expect do
        described_class.from_hash(requirement_hash.merge(groups: ["default", 1]))
      end.to raise_error(TypeError, "groups must be an array of strings or symbols, or nil")

      expect do
        described_class.from_hash(requirement_hash.merge(source: "rubygems"))
      end.to raise_error(TypeError, "source must be a hash or nil")

      expect do
        described_class.from_hash(requirement_hash.merge(metadata: "rails.version"))
      end.to raise_error(TypeError, "metadata must be a hash or nil")
    end

    it "accepts the unfixable requirement sentinel" do
      requirement = described_class.from_hash(requirement_hash.merge(requirement: :unfixable))

      expect(requirement).to be_unfixable
      expect(requirement.requirement).to be_nil
      expect(requirement.to_h[:requirement]).to eq(:unfixable)
    end

    it "rejects other requirement symbols" do
      expect do
        described_class.from_hash(requirement_hash.merge(requirement: :unknown))
      end.to raise_error(TypeError, "requirement must be a string, :unfixable, or nil")
    end
  end

  describe "typed readers" do
    subject(:requirement) { described_class.from_hash(requirement_hash) }

    it "exposes the well-known keys" do
      expect(requirement.requirement).to eq(">= 1.0, < 2.0")
      expect(requirement.file).to eq("Gemfile")
      expect(requirement.groups).to eq([:default])
      expect(requirement.source).to eq(type: "rubygems", url: "https://rubygems.org")
      expect(requirement.metadata).to eq(property_name: "rails.version")
    end

    it "returns nil for absent optional keys" do
      minimal = described_class.from_hash(requirement: nil, file: "Gemfile", groups: [], source: nil)

      expect(minimal.requirement).to be_nil
      expect(minimal.source).to be_nil
      expect(minimal.metadata).to be_nil
    end

    it "returns nil groups without raising when the entry has groups: nil" do
      req = described_class.from_hash(requirement: ">= 1.0", file: "Gemfile", groups: nil, source: nil)

      expect(req.groups).to be_nil
    end

    it "preserves mixed string and symbol groups" do
      req = described_class.from_hash(
        requirement: ">= 1.0",
        file: "Gemfile",
        groups: ["development", :default],
        source: nil
      )

      expect(req.groups).to eq(["development", :default])
    end
  end

  describe "typed copies" do
    subject(:requirement) { described_class.from_hash(requirement_hash) }

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
      without_metadata = described_class.from_hash(
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

  describe "value semantics" do
    subject(:requirement) { described_class.from_hash(requirement_hash) }

    it "does not expose the Hash API" do
      expect(requirement).not_to respond_to(:[])
      expect(requirement).not_to respond_to(:fetch)
      expect(requirement).not_to respond_to(:dig)
      expect(requirement).not_to respond_to(:merge)
    end

    it "compares equal to another requirement with the same content" do
      copy = described_class.from_hash(requirement_hash)

      expect(requirement).to eq(copy)
      expect(requirement.eql?(copy)).to be(true)
      expect(requirement.hash).to eq(copy.hash)
      expect(requirement).not_to eq(requirement_hash)
    end

    it "interoperates in Array and Set operations by value" do
      copy = described_class.from_hash(requirement_hash)

      expect([requirement] - [copy]).to be_empty
      expect([requirement, copy].uniq.length).to eq(1)
      expect(Set.new([requirement])).to include(copy)
    end

    it "freezes collection fields" do
      expect(requirement.groups).to be_frozen
      expect(requirement.source).to be_frozen
      expect(requirement.metadata).to be_frozen
    end
  end
end
