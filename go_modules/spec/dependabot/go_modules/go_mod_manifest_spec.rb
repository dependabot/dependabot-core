# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/go_mod_manifest"

RSpec.describe Dependabot::GoModules::GoModManifest do
  subject(:manifest) { described_class.from_json(content, file_path: file_path) }

  let(:file_path) { "/services/api/go.mod" }
  let(:content) { JSON.generate(data) }
  let(:data) do
    {
      "Require" => [
        { "Path" => "rsc.io/quote", "Version" => "v1.4.0" },
        { "Path" => "golang.org/x/sys", "Version" => "v0.0.0-20200922070232-aee5d888a860", "Indirect" => true }
      ],
      "Replace" => [
        { "Old" => { "Path" => "rsc.io/qr" }, "New" => { "Path" => "../local" } },
        {
          "Old" => { "Path" => "rsc.io/quote", "Version" => "v1.4.0" },
          "New" => { "Path" => "example.com/quote", "Version" => "v1.5.0" }
        }
      ],
      "Exclude" => [{ "Path" => "rsc.io/quote", "Version" => "v1.3.0" }]
    }
  end

  it "returns typed requirements, replacements, and exclusions" do
    expect(manifest.requirements.first).to be_a(described_class::RequirementEntry)
    expect(manifest.requirements.first).to have_attributes(path: "rsc.io/quote", version: "v1.4.0", indirect: false)
    expect(manifest.requirements.last).to have_attributes(
      path: "golang.org/x/sys", version: "v0.0.0-20200922070232-aee5d888a860", indirect: true
    )
    expect(manifest.replacements.first).to be_a(described_class::Replacement)
    expect(manifest.replacements.first.old).to have_attributes(path: "rsc.io/qr", version: nil)
    expect(manifest.replacements.first.new).to have_attributes(path: "../local", version: nil)
    expect(manifest.replacements.last.old).to have_attributes(path: "rsc.io/quote", version: "v1.4.0")
    expect(manifest.replacements.last.new).to have_attributes(path: "example.com/quote", version: "v1.5.0")
    expect(manifest.exclusions.first).to be_a(described_class::Exclusion)
    expect(manifest.exclusions.first).to have_attributes(path: "rsc.io/quote", version: "v1.3.0")
  end

  it "decodes the real Go command's output" do
    go_mod = fixture("projects", "replace", "go.mod")
    Dependabot::SharedHelpers.in_a_temporary_directory do
      File.write("go.mod", go_mod)
      result = described_class.from_json(
        Dependabot::SharedHelpers.run_shell_command("go mod edit -json"),
        file_path: file_path
      )

      expect(result.requirements.map(&:path)).to include("rsc.io/quote")
      expect(result.replacements.map { |replacement| replacement.new.path }).to include("../../../../../../foo")
      expect(result.exclusions).to be_empty
    end
  end

  [
    {},
    { "Require" => nil, "Replace" => nil, "Exclude" => nil },
    { "Require" => [], "Replace" => [], "Exclude" => [] }
  ].each do |fields|
    context "with empty sections #{fields}" do
      let(:data) { fields }

      it "returns empty typed lists" do
        expect(manifest.requirements).to eq([])
        expect(manifest.replacements).to eq([])
        expect(manifest.exclusions).to eq([])
      end
    end
  end

  context "with unused fields" do
    let(:data) { super().merge("Module" => false, "Go" => [], "Retract" => "ignored", "Future" => { "value" => nil }) }

    it "does not parse fields outside the consumed projection" do
      expect(manifest.requirements.first.path).to eq("rsc.io/quote")
    end
  end

  context "with duplicate entries" do
    let(:data) { super().transform_values { |entries| entries.reverse + entries } }

    it "preserves order and duplicates" do
      expect(manifest.requirements.map(&:path)).to eq(
        %w(golang.org/x/sys rsc.io/quote rsc.io/quote golang.org/x/sys)
      )
      expect(manifest.replacements.map { |replacement| replacement.old.path })
        .to eq(%w(rsc.io/quote rsc.io/qr rsc.io/qr rsc.io/quote))
      expect(manifest.exclusions.map(&:version)).to eq(%w(v1.3.0 v1.3.0))
    end
  end

  [nil, false, true].each do |value|
    context "with Indirect #{value.inspect}" do
      let(:data) { { "Require" => [{ "Path" => "example.com/module", "Indirect" => value }] } }

      it "preserves the direct or indirect classification" do
        expect(manifest.requirements.first.indirect).to eq(value == true)
        expect(manifest.requirements.first.version).to be_nil
      end
    end
  end

  [nil, "", "main", "v2.0.0+incompatible"].each do |value|
    context "with optional version #{value.inspect}" do
      let(:data) do
        {
          "Require" => [{ "Path" => "example.com/module", "Version" => value }],
          "Replace" => [{
            "Old" => { "Path" => "example.com/module", "Version" => value },
            "New" => { "Path" => "../local", "Version" => value }
          }]
        }
      end

      it "does not normalize optional version strings" do
        expect(manifest.requirements.first.version).to eq(value)
        expect(manifest.replacements.first.old.version).to eq(value)
        expect(manifest.replacements.first.new.version).to eq(value)
      end
    end
  end

  shared_examples "invalid output" do |field|
    it "reports the command, original manifest, and invalid field without payload data" do
      expect { manifest }.to raise_error(described_class::InvalidOutput) do |error|
        expect(error).to be_a(Dependabot::SharedHelpers::HelperSubprocessFailed)
        expect(error.message).to include("go mod edit -json", file_path, field)
        expect(error.message).not_to include("do-not-echo-this")
        expect(error.error_context).to eq(command: "go mod edit -json")
        expect(error.cause).to be_nil
      end
    end
  end

  context "with invalid JSON" do
    let(:content) { '{"do-not-echo-this":' }

    it_behaves_like "invalid output", "valid JSON"
  end

  [nil, false, [], 42, "do-not-echo-this"].each do |value|
    context "with root #{value.inspect}" do
      let(:data) { value }

      it_behaves_like "invalid output", "result must be an object"
    end
  end

  invalid_sections = [false, {}, 42, "do-not-echo-this"]
  invalid_entries = [nil, false, [], "do-not-echo-this"]
  %w(Require Replace Exclude).each do |section|
    invalid_sections.each do |value|
      context "with #{section} #{value.inspect}" do
        let(:data) { super().merge(section => value) }

        it_behaves_like "invalid output", "#{section} must be an array"
      end
    end

    invalid_entries.each do |value|
      context "with a malformed trailing #{section} entry #{value.inspect}" do
        let(:data) { super().tap { |fields| fields.fetch(section) << value } }
        let(:invalid_index) { section == "Exclude" ? 1 : 2 }
        let(:invalid_context) { "go mod edit -json for #{file_path}" }

        it "parses the whole list before returning any results" do
          expect { manifest }.to raise_error(
            described_class::InvalidOutput, "#{invalid_context}: #{section}[#{invalid_index}] must be an object"
          )
        end
      end
    end
  end

  [0, 1, "false", [], {}].each do |value|
    context "with invalid Indirect #{value.inspect}" do
      let(:data) { { "Require" => [{ "Path" => "example.com/module", "Indirect" => value }] } }

      it_behaves_like "invalid output", "Require[0].Indirect must be a boolean or nil"
    end
  end

  {
    "Require[0].Path" => { "Require" => [{ "Version" => "v1.0.0" }] },
    "Require[0].Version" => { "Require" => [{ "Path" => "example.com/module", "Version" => false }] },
    "Require[0].Indirect" => { "Require" => [{ "Path" => "example.com/module", "Indirect" => "do-not-echo-this" }] },
    "Replace[0].Old" => { "Replace" => [{ "New" => { "Path" => "../local" } }] },
    "Replace[0].New" => { "Replace" => [{ "Old" => { "Path" => "example.com/module" }, "New" => false }] },
    "Replace[0].Old.Path" => { "Replace" => [{ "Old" => {} }] },
    "Replace[0].Old.Version" => { "Replace" => [{ "Old" => { "Path" => "example.com/module", "Version" => [] } }] },
    "Replace[0].New.Path" => { "Replace" => [{ "Old" => { "Path" => "example.com/module" }, "New" => {} }] },
    "Replace[0].New.Version" => {
      "Replace" => [{ "Old" => { "Path" => "example.com/module" },
                      "New" => { "Path" => "../local", "Version" => false } }]
    },
    "Exclude[0].Path" => { "Exclude" => [{ "Path" => false, "Version" => "v1.0.0" }] },
    "Exclude[0].Version" => { "Exclude" => [{ "Path" => "example.com/module" }] }
  }.each do |field, fields|
    context "with malformed #{field}" do
      let(:data) { fields }

      it_behaves_like "invalid output", field
    end
  end
end
