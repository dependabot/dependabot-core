# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/file_parser/bun_lock"

RSpec.describe Dependabot::Bun::FileParser::BunLock do
  subject(:reader) { described_class.new(file) }

  let(:file) { Dependabot::DependencyFile.new(name: "bun.lock", content: data.to_json) }
  let(:entry) { ["example@1.2.0", "https://registry.example", { "dependencies" => { "child" => "^1" } }, "integrity"] }
  let(:data) { { "lockfileVersion" => 0, "packages" => { "example" => entry } } }

  it "exposes typed package records" do
    record = reader.records.fetch("example")
    expect(record).to have_attributes(name: "example", version: "1.2.0", dependency_names: ["child"])
  end

  it "does not reinterpret the registry field as a resolved URL" do
    expect(reader.details("example", "^9", "package.json"))
      .to have_attributes(version: "1.2.0", resolved: nil, resolution: nil)
  end

  it "returns no details for a missing package key" do
    expect(reader.details("missing", nil, "package.json")).to be_nil
  end

  context "with a nested package key" do
    let(:data) { { "lockfileVersion" => 1, "packages" => { "parent/example" => entry } } }

    it "keeps lookup keys separate from names" do
      expect(reader.details("example", nil, "package.json")).to be_nil
      expect(reader.details("parent/example", nil, "package.json").version).to eq("1.2.0")
      expect(reader.dependencies.dependencies.first.name).to eq("example")
    end
  end

  context "with a non-registry tuple" do
    let(:entry) { ["example@file:../local", { "dependencies" => { "hidden" => "1" } }] }

    it "preserves the resolution without inventing a version or URL" do
      expect(reader.details("example", nil, "package.json"))
        .to have_attributes(version: nil, resolved: nil, resolution: "file:../local")
    end

    it "does not add graph edges from slot-one details" do
      expect(reader.records.fetch("example").dependency_names).to be_empty
      expect(reader.dependencies.dependencies).to be_empty
    end
  end

  context "with unused tuple fields" do
    let(:entry) { ["example@1.2.0", [], "unconsumed", false] }

    it "does not decode them for dependency or version lookup" do
      expect(reader.dependencies.dependencies.first.version).to eq("1.2.0")
      expect(reader.details("example", nil, "package.json").version).to eq("1.2.0")
    end

    it "reports malformed details only when graph data is requested" do
      expect { reader.records.fetch("example").dependency_names }
        .to raise_error(Dependabot::DependencyFileNotParseable, /packages.*example.*details must be an object/)
    end
  end

  describe "record edge names" do
    let(:entry) do
      [
        "example@1.2.0",
        "",
        {
          "dependencies" => { "child" => "^1" },
          "optionalDependencies" => { "optional" => "^1" },
          "peerDependencies" => { "peer" => "*", "child" => "^1" },
          "devDependencies" => { "ignored" => "^1" }
        },
        "integrity"
      ]
    end

    it "lists installed children once, without dev dependencies" do
      expect(reader.records.fetch("example").edge_names).to eq(%w(child optional peer))
    end

    context "with slot-one details" do
      let(:entry) do
        ["example@github:owner/example#abc", { "dependencies" => { "hidden" => "1" } }, "owner-example-abc"]
      end

      it "reads edges from slot one" do
        expect(reader.records.fetch("example").edge_names).to eq(["hidden"])
      end
    end

    context "with a workspace link" do
      let(:entry) { ["app@workspace:packages/app"] }

      it "has no edges" do
        expect(reader.records.fetch("example").edge_names).to be_empty
      end
    end

    [[], ["example@1.2.0", "", []], ["example@1.2.0", "", { "dependencies" => [] }]].each do |value|
      context "with #{value.inspect} as a package tuple" do
        let(:entry) { value }

        it "gives no edges instead of raising" do
          expect(reader.records.fetch("example").edge_names).to be_empty
        end
      end
    end
  end

  describe "#workspaces" do
    let(:data) do
      {
        "lockfileVersion" => 1,
        "workspaces" => {
          "" => {
            "name" => "root",
            "dependencies" => { "debug" => "4.3.4" },
            "devDependencies" => { "ms" => "0.7.1" },
            "peerDependencies" => { "typescript" => "^5" }
          },
          "packages/app" => {
            "name" => "app",
            "optionalDependencies" => { "fsevents" => "*" },
            "devDependencies" => { "is-number" => "7.0.0" }
          },
          "packages/unnamed" => { "dependencies" => { "lodash" => "*" } }
        },
        "packages" => {}
      }
    end

    it "reads each workspace as a graph root" do
      expect(reader.workspaces.map { |w| [w.key_prefix, w.production_names, w.development_names] }).to eq(
        [
          [nil, %w(debug typescript), ["ms"]],
          ["app", ["fsevents"], ["is-number"]],
          [nil, ["lodash"], []]
        ]
      )
    end

    context "without a workspaces object" do
      let(:data) { { "lockfileVersion" => 1, "workspaces" => [], "packages" => {} } }

      it "has no roots" do
        expect(reader.workspaces).to be_empty
      end
    end

    context "with malformed workspace entries" do
      let(:data) { { "lockfileVersion" => 1, "workspaces" => { "" => "invalid" }, "packages" => {} } }

      it "skips them" do
        expect(reader.workspaces).to be_empty
      end
    end
  end

  context "with unconsumed dependency requirement values" do
    let(:entry) { ["example@1.2.0", "", { "dependencies" => { "child" => [], "second" => nil } }] }

    it "preserves child names without parsing unused ranges" do
      expect(reader.records.fetch("example").dependency_names).to eq(%w(child second))
    end
  end

  [nil, "invalid", [1], []].each do |value|
    context "with #{value.inspect} as a package tuple" do
      let(:entry) { value }

      it "reports malformed data for dependency parsing" do
        expect { reader.dependencies }.to raise_error(Dependabot::DependencyFileNotParseable)
      end

      it "preserves the graph's structural filter" do
        expect(reader.records.fetch("example").graph_compatible?).to be(false)
      end
    end
  end

  context "with no packages map" do
    let(:data) { { "lockfileVersion" => 0 } }

    it "preserves the optional graph and lookup view" do
      expect(reader.records).to be_nil
      expect(reader.details("example", nil, "package.json")).to be_nil
    end

    it "still rejects the missing map for dependency enumeration" do
      expect { reader.dependencies }.to raise_error(Dependabot::DependencyFileNotParseable, /packages/)
    end
  end

  it "leaves file content unchanged" do
    original = file.content.dup
    reader.dependencies
    reader.details("example", nil, "package.json")
    expect(file.content).to eq(original)
  end
end
