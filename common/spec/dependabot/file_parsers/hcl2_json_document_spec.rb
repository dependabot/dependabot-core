# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_parsers/hcl2_json_document"

RSpec.describe Dependabot::FileParsers::Hcl2JsonDocument do
  extend T::Sig

  sig { returns(Dependabot::FileParsers::Hcl2JsonDocument) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:document) { described_class.from_helper_output(data.to_json, file: file) }

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::DependencyFile) }
  let(:file) { Dependabot::DependencyFile.new(name: "main.tf", content: "") }

  sig { returns(T::Hash[String, Object]) }
  let(:data) do
    {
      "module" => {
        "main" => [{ "source" => "hashicorp/main/aws", "version" => "~> 1", "future" => false }],
        "local" => [{ "source" => "./local", "version" => false }]
      }
    }
  end
  # rubocop:enable RSpec/ScatteredLet

  it "merges partial override blocks before interpreting effective declarations" do
    override = described_class.from_helper_output(
      {
        "module" => {
          "main" => [{ "version" => nil }],
          "added" => [{ "source" => "hashicorp/added/aws", "version" => "~> 2" }]
        }
      }.to_json,
      file: Dependabot::DependencyFile.new(name: "override.tf", content: "")
    )
    declarations = document.module_declarations(overrides: [override])

    expect(declarations.map(&:name)).to eq(%w(main local added))
    expect(declarations.fetch(0)).to have_attributes(source: "hashicorp/main/aws", version: nil)
    expect(declarations.fetch(1).source).to eq("./local")
    expect { declarations.fetch(1).version }
      .to raise_error(Dependabot::DependencyFileNotParseable, /local\.version/)
  end

  context "with providers and local values" do
    sig { returns(T::Hash[String, Object]) }
    let(:data) do
      {
        "terraform" => [{
          "required_providers" => [{
            "modern" => { "source" => "hashicorp/aws", "version" => false },
            "legacy" => "~> 1"
          }]
        }],
        "locals" => [{ "version" => "1.2", "expression" => "${local.other}", "ignored" => 42 }]
      }
    end

    it "retains provider syntax variants without consuming unused versions" do
      providers = document.provider_declarations

      expect(providers.fetch(0)).to have_attributes(name: "modern", source: "hashicorp/aws")
      expect(providers.fetch(1)).to be_a(Dependabot::FileParsers::Hcl2JsonDocument::DeprecatedProvider)
      expect(document.local_strings).to eq("version" => "1.2", "expression" => "${local.other}")
    end
  end

  context "with provider lock records and unrelated malformed data" do
    sig { returns(T::Hash[String, Object]) }
    let(:data) do
      { "provider" => { "registry.example/ns/name" => [{ "version" => "1.2.3" }] }, "module" => false }
    end

    it "reads only the requested provider version" do
      expect(document.provider_version("registry.example/ns/name")).to eq("1.2.3")
      expect(document.provider_version("missing")).to be_nil
    end
  end

  context "with an empty module block list" do
    sig { returns(T::Hash[String, Object]) }
    let(:data) { { "module" => { "broken" => [] } } }

    it "reports the declaration and file instead of dereferencing a missing block" do
      expect { document.module_declarations }
        .to raise_error(Dependabot::DependencyFileNotParseable, /module\.broken/) do |error|
        expect(error.file_path).to eq(file.path)
      end
    end
  end
end
