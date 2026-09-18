# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/composer/manifest_document"

RSpec.describe Dependabot::Composer::ManifestDocument do
  subject(:document) { described_class.from_file(file) }

  let(:file) { Dependabot::DependencyFile.new(name: "composer.json", content: data.to_json) }
  let(:data) do
    {
      "name" => "vendor/project",
      "require" => { "vendor/first" => "^1", "vendor/second" => false },
      "require-dev" => { "vendor/dev" => "*" },
      "config" => { "platform" => { "php" => "8.0" } },
      "repositories" => false
    }
  end

  it "retains ordered dependency entries without validating unused requirements" do
    entries = document.requirements("require")

    expect(entries.map(&:name)).to eq(%w(vendor/first vendor/second))
    expect(entries.first.requirement).to eq("^1")
    expect(entries.last.string_requirement).to be_nil
    expect(document.required_dependency_names).to eq(%w(vendor/first vendor/second))
    expect(document.requirements("require-dev").map(&:name)).to eq(["vendor/dev"])
  end

  it "rejects a malformed requirement only when consumed" do
    expect { document.requirements("require").last.requirement }
      .to raise_error(TypeError, /composer.json.*require.*string/)
  end

  it "reads names and platform constraints without inspecting repositories" do
    expect(document.name).to eq("vendor/project")
    expect(document.platform("php")).to eq("8.0")
    expect(document.dependency_constraint("vendor/first")).to eq("^1")
  end

  context "with missing sections" do
    let(:data) { {} }

    it "returns empty collections and absent optional fields" do
      expect(document.requirements("require")).to eq([])
      expect(document.required_dependency_names).to eq([])
      expect(document.name).to be_nil
      expect(document.platform("php")).to be_nil
      expect(document.dependency_constraint("php")).to be_nil
    end
  end

  context "with a null requirement section" do
    let(:data) { { "require" => nil } }

    it "preserves enumeration tolerance without weakening the naming check" do
      expect(document.requirements("require")).to eq([])
      expect(document.dependency_constraint("php")).to be_nil
      expect { document.required_dependency_names }.to raise_error(TypeError, /require.*object/)
    end
  end

  context "with false scalar fields" do
    let(:data) { { "name" => false, "config" => { "platform" => { "php" => false } } } }

    it "preserves name truthiness and rejects a consumed non-string platform version" do
      expect(document.name).to be_nil
      expect { document.platform("php") }.to raise_error(TypeError, /config.platform.php.*string/)
    end
  end
end
