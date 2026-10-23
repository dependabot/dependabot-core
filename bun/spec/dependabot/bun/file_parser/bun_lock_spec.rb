# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/file_parser/bun_lock"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe Dependabot::Bun::FileParser::BunLock do
  extend T::Sig

  sig { returns(Dependabot::Bun::FileParser::BunLock) }
  subject(:reader) { described_class.new(file) }

  sig { returns(Dependabot::DependencyFile) }
  let(:file) { Dependabot::DependencyFile.new(name: "bun.lock", content: data.to_json) }
  sig { returns(Object) }
  let(:entry) { ["example@1.2.0", "https://registry.example", { "dependencies" => { "child" => "^1" } }, "integrity"] }
  sig { returns(T::Hash[String, Object]) }
  let(:data) { { "lockfileVersion" => 0, "packages" => { "example" => entry } } }

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_yarn_berry_conflicting_dependencies).and_return(true)
  end

  context "when the experiment is disabled" do
    sig { returns(Object) }
    let(:entry) do
      [
        "example@1.2.0", "",
        {
          "dependencies" => { "child" => "^1" },
          "optionalDependencies" => { "optional" => "^1" },
          "peerDependencies" => { "peer" => "^1" }
        }
      ]
    end

    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_yarn_berry_conflicting_dependencies).and_return(false)
    end

    it "retains the original dependency edge kinds used for graphing" do
      expect(T.must(reader.records).fetch("example").dependency_names).to eq(["child"])
    end
  end

  it "exposes typed package records" do
    record = T.must(reader.records).fetch("example")
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
    sig { returns(T::Hash[String, Object]) }
    let(:data) { { "lockfileVersion" => 1, "packages" => { "parent/example" => entry } } }

    it "keeps lookup keys separate from names" do
      expect(reader.details("example", nil, "package.json")).to be_nil
      expect(T.must(reader.details("parent/example", nil, "package.json")).version).to eq("1.2.0")
      expect(T.must(reader.dependencies.dependencies.first).name).to eq("example")
    end
  end

  context "with a non-registry tuple" do
    sig { returns(Object) }
    let(:entry) { ["example@file:../local", { "dependencies" => { "hidden" => "1" } }] }

    it "preserves the resolution without inventing a version or URL" do
      expect(reader.details("example", nil, "package.json"))
        .to have_attributes(version: nil, resolved: nil, resolution: "file:../local")
    end

    it "reads graph edges from the non-registry metadata slot" do
      expect(T.must(reader.records).fetch("example").dependency_names).to eq(["hidden"])
      expect(reader.dependencies.dependencies).to be_empty
    end
  end

  context "with unused tuple fields" do
    sig { returns(Object) }
    let(:entry) { ["example@1.2.0", [], "unconsumed", false] }

    it "does not decode them for dependency or version lookup" do
      expect(T.must(reader.dependencies.dependencies.first).version).to eq("1.2.0")
      expect(T.must(reader.details("example", nil, "package.json")).version).to eq("1.2.0")
    end

    it "reports malformed details only when graph data is requested" do
      expect { T.must(reader.records).fetch("example").dependency_names }
        .to raise_error(Dependabot::DependencyFileNotParseable, /packages.*example.*details must be an object/)
    end
  end

  context "with unconsumed dependency requirement values" do
    sig { returns(Object) }
    let(:entry) { ["example@1.2.0", "", { "dependencies" => { "child" => [], "second" => nil } }] }

    it "preserves child names without parsing unused ranges" do
      expect(T.must(reader.records).fetch("example").dependency_names).to eq(%w(child second))
    end
  end

  it "rejects malformed package tuples and preserves the graph's structural filter" do
    [nil, "invalid", [1], []].each do |value|
      malformed = Dependabot::DependencyFile.new(
        name: "bun.lock", content: { "lockfileVersion" => 0, "packages" => { "example" => value } }.to_json
      )
      malformed_reader = described_class.new(malformed)
      expect { malformed_reader.dependencies }.to raise_error(Dependabot::DependencyFileNotParseable)
      expect(T.must(malformed_reader.records).fetch("example").graph_compatible?).to be(false)
    end
  end

  context "with no packages map" do
    sig { returns(T::Hash[String, Object]) }
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
    original = T.must(file.content).dup
    reader.dependencies
    reader.details("example", nil, "package.json")
    expect(file.content).to eq(original)
  end
end
