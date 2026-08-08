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

  describe "source helpers" do
    it "reads symbol-keyed source fields" do
      req = described_class.create(requirement_hash)

      expect(req.source_hash).to eq(type: "rubygems", url: "https://rubygems.org")
      expect(req.source_string("type")).to eq("rubygems")
      expect(req.source_string("url")).to eq("https://rubygems.org")
    end

    it "reads string-keyed source fields" do
      req = described_class.create(
        requirement_hash.merge(source: { "type" => "git", "ref" => "main" })
      )

      expect(req.source_string("type")).to eq("git")
      expect(req.source_string("ref")).to eq("main")
    end

    it "returns nil for absent source fields" do
      req = described_class.create(requirement_hash)

      expect(req.source_string("ref")).to be_nil
    end

    it "returns nil when the requirement has no source" do
      req = described_class.create(requirement_hash.merge(source: nil))

      expect(req.source_hash).to be_nil
      expect(req.source_string("type")).to be_nil
    end

    it "returns nil when the source is a registry name string" do
      req = described_class.create(requirement_hash.merge(source: "internal"))

      expect(req.source_hash).to be_nil
      expect(req.source_string("type")).to be_nil
    end

    it "rejects a non-string value under a known source key" do
      req = described_class.create(requirement_hash.merge(source: { type: 1 }))

      expect { req.source_string("type") }
        .to raise_error(TypeError, "source type must be a string or nil")
    end

    it "rejects a malformed source container" do
      req = described_class.create(requirement_hash.merge(source: []))

      expect { req.source_hash }
        .to raise_error(TypeError, "source must be a string or hash with string or symbol keys, or nil")
    end
  end

  describe "#requirement_string" do
    it "returns a string requirement" do
      req = described_class.create(requirement_hash)

      expect(req.requirement_string).to eq(">= 1.0, < 2.0")
    end

    it "returns nil when the requirement is absent" do
      req = described_class.create(requirement_hash.merge(requirement: nil))

      expect(req.requirement_string).to be_nil
    end

    it "rejects the unfixable sentinel" do
      req = described_class.create(requirement_hash.merge(requirement: :unfixable))

      expect { req.requirement_string }
        .to raise_error(TypeError, "requirement must be a string or nil")
    end
  end

  describe "metadata helpers" do
    it "reads a symbol-keyed metadata string" do
      req = described_class.create(requirement_hash)

      expect(req.metadata_string("property_name")).to eq("rails.version")
    end

    it "reads a string-keyed metadata string" do
      req = described_class.create(
        requirement_hash.merge(metadata: { "property_name" => "rails.version" })
      )

      expect(req.metadata_string("property_name")).to eq("rails.version")
    end

    it "returns nil when the metadata key is absent" do
      req = described_class.create(requirement_hash)

      expect(req.metadata_string("dependency_set")).to be_nil
    end

    it "returns nil when the requirement has no metadata" do
      req = described_class.create(requirement_hash.merge(metadata: nil))

      expect(req.metadata_string("property_name")).to be_nil
      expect(req.metadata_string_hash("dependency_set")).to be_nil
    end

    it "rejects a non-string metadata value" do
      req = described_class.create(requirement_hash.merge(metadata: { property_name: 1 }))

      expect { req.metadata_string("property_name") }
        .to raise_error(TypeError, "metadata property_name must be a string or nil")
    end

    it "reads a symbol metadata value" do
      req = described_class.create(requirement_hash.merge(metadata: { type: :helm_chart }))

      expect(req.metadata_symbol("type")).to eq(:helm_chart)
    end

    it "reads a symbol value from string-keyed metadata" do
      req = described_class.create(requirement_hash.merge(metadata: { "type" => :docker_image }))

      expect(req.metadata_symbol("type")).to eq(:docker_image)
    end

    it "returns nil for an absent symbol metadata value" do
      req = described_class.create(requirement_hash)

      expect(req.metadata_symbol("type")).to be_nil
    end

    it "rejects a non-symbol metadata value" do
      req = described_class.create(requirement_hash.merge(metadata: { type: "helm_chart" }))

      expect { req.metadata_symbol("type") }
        .to raise_error(TypeError, "metadata type must be a symbol or nil")
    end

    it "reads a metadata hash of strings" do
      req = described_class.create(
        requirement_hash.merge(metadata: { dependency_set: { group: "my.group", version: "1.4.0" } })
      )

      expect(req.metadata_string_hash("dependency_set"))
        .to eq(group: "my.group", version: "1.4.0")
    end

    it "symbolises string keys in a metadata hash" do
      req = described_class.create(
        requirement_hash.merge(metadata: { dependency_set: { "group" => "my.group" } })
      )

      expect(req.metadata_string_hash("dependency_set")).to eq(group: "my.group")
    end

    it "rejects a metadata hash that is not a hash" do
      req = described_class.create(requirement_hash.merge(metadata: { dependency_set: "nope" }))

      expect { req.metadata_string_hash("dependency_set") }
        .to raise_error(TypeError, "metadata dependency_set must be a hash of strings or nil")
    end

    it "rejects a non-string value inside a metadata hash" do
      req = described_class.create(requirement_hash.merge(metadata: { dependency_set: { group: 1 } }))

      expect { req.metadata_string_hash("dependency_set") }
        .to raise_error(TypeError, "metadata dependency_set must be a hash of strings or nil")
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
