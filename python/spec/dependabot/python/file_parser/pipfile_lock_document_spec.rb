# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/file_parser/pipfile_lock_document"

RSpec.describe Dependabot::Python::FileParser::PipfileLockDocument do
  extend T::Sig

  sig { returns(Dependabot::Python::FileParser::PipfileLockDocument) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:document) { described_class.from_file(file) }

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::DependencyFile) }
  let(:file) { Dependabot::DependencyFile.new(name: "Pipfile.lock", content: data.to_json) }
  sig { returns(T::Hash[String, Object]) }
  let(:data) do
    {
      "default" => {
        "String_Pin" => "  ==1  ",
        "table" => { "version" => "  ==2  " },
        "path" => { "version" => 123, "path" => nil },
        "ignored" => [false]
      },
      "develop" => false
    }
  end
  # rubocop:enable RSpec/ScatteredLet

  it "preserves stored names and tolerant enumeration" do
    entries = document.entries("default")
    expect(entries.map(&:name)).to eq(%w(String_Pin table path))
    expect(entries.map(&:lockfile_version)).to eq(["  ==1  ", "  ==2  ", nil])
    expect(document.entries("develop")).to eq([])
  end

  it "strips lookup strings without normalizing stored keys or table versions" do
    expect(document.version_for("default", "String_Pin")).to eq("==1")
    expect(document.version_for("default", "string-pin")).to be_nil
    expect(document.version_for("default", "table")).to eq("  ==2  ")
    expect(document.version_for("default", "ignored")).to be_nil
    expect(document.version_for("develop", "anything")).to be_nil
  end

  it "reads dependency names without decoding unrelated entry values" do
    expect(document.dependency_names("default")).to eq(%w(String_Pin table path ignored))
    expect(document.dependency_names("missing")).to eq([])
  end

  describe "metadata restoration" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(T::Hash[String, Object]) }
    let(:data) do
      {
        "_meta" => {
          "hash" => { "sha256" => "generated", "other" => "kept" },
          "requires" => { "python_version" => "3.15" },
          "sources" => [],
          "pipfile-spec" => 6
        },
        "default" => { "requests" => { "version" => "==2.32.0", "future" => [false] } },
        "future" => { "opaque" => true }
      }
    end

    sig { returns(Dependabot::Python::FileParser::PipfileLockDocument::PreservedMetadata) }
    let(:metadata) do
      original = described_class.new(
        data: {
          "_meta" => {
            "requires" => { "python_version" => "3.10" },
            "sources" => [{ "url" => "https://example.com/${TOKEN}", "verify_ssl" => false, "future" => 1 }]
          }
        },
        context: "Pipfile.lock"
      )
      original.preserved_metadata
    end
    # rubocop:enable RSpec/ScatteredLet

    it "restores selected metadata while preserving generated and unknown fields" do
      content = document.restored_content(metadata: metadata, checksum: "updated")
      parsed = JSON.parse(content)

      expect(parsed["_meta"]).to eq(
        "hash" => { "sha256" => "updated", "other" => "kept" },
        "requires" => metadata.requires,
        "sources" => metadata.sources,
        "pipfile-spec" => 6
      )
      expect(parsed["default"]).to eq(data["default"])
      expect(parsed["future"]).to eq(data["future"])
      expect(content).to end_with("}\n")
      expect(document.preserved_metadata.requires).to eq("python_version" => "3.15")
    end

    context "with a malformed generated checksum container" do
      sig { returns(T::Hash[String, Object]) }
      let(:data) { { "_meta" => { "hash" => false } } }

      it "reports the consumed field and file path" do
        expect { document.restored_content(metadata: metadata, checksum: "updated") }
          .to raise_error(Dependabot::DependencyFileNotParseable, /Pipfile\.lock _meta\.hash/)
      end
    end
  end

  context "with malformed metadata" do
    sig { returns(T::Hash[String, Object]) }
    let(:data) { { "_meta" => false } }

    it "reports the metadata field and file path" do
      expect { document.preserved_metadata }
        .to raise_error(Dependabot::DependencyFileNotParseable, /Pipfile\.lock _meta/)
    end
  end

  context "with a scalar entry" do
    sig { returns(T::Hash[String, Object]) }
    let(:data) { { "default" => { "bad" => false } } }

    it "keeps enumeration skips distinct from lookup failures" do
      expect(document.entries("default")).to eq([])
      expect { document.version_for("default", "bad") }.to raise_error(TypeError, /Pipfile.lock.*entry/)
    end
  end

  context "with invalid JSON" do
    sig { returns(Dependabot::DependencyFile) }
    let(:file) { Dependabot::DependencyFile.new(name: "Pipfile.lock", content: "{ invalid") }

    it "reports the file path" do
      expect { document }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
        expect(error.file_name).to eq("Pipfile.lock")
      end
    end
  end
end
