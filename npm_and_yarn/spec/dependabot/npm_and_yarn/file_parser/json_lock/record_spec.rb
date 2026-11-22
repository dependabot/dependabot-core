# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_parser/json_lock"

RSpec.describe Dependabot::NpmAndYarn::FileParser::JsonLock::Record do
  extend T::Sig

  sig { returns(Dependabot::NpmAndYarn::FileParser::JsonLock::Record) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:record) { described_class.new(data, path: "nested/package-lock.json", context: "lockfile") }

  sig { returns(T::Hash[String, Object]) }
  let(:data) do
    {
      "packages" => {
        "" => { "name" => "project", "dependencies" => { "example" => "^1.0", "unused" => false } },
        "unused" => false
      },
      "dependencies" => {
        "git" => { "version" => "git+https://example.com/repo#sha", "from" => "repo#main" },
        "regular" => { "version" => "1.0.0", "from" => false }
      }
    }
  end

  it "reads only the selected root requirement" do
    root = T.must(record.root_package)

    expect(root.name).to eq("project")
    expect(root.requirement("dependencies", "example")).to eq("^1.0")
    expect(root.requirement("devDependencies", "missing")).to be_nil
  end

  it "retains git pin fields without decoding metadata for non-git versions" do
    pin = T.must(T.must(record.legacy_entries["git"]).git_pin)

    expect(pin).to have_attributes(version: "git+https://example.com/repo#sha", from: "repo#main")
    expect(T.must(record.legacy_entries["regular"]).git_pin).to be_nil
  end

  it "reports a malformed consumed requirement with its file path" do
    expect { T.must(record.root_package).requirement("dependencies", "unused") }
      .to raise_error(Dependabot::DependencyFileNotParseable, /dependencies\.unused/) do |error|
      expect(error.file_path).to eq("nested/package-lock.json")
    end
  end

  context "without a root package" do
    sig { returns(T::Hash[String, Object]) }
    let(:data) { { "packages" => { "node_modules/example" => { "version" => "1.0" } } } }

    it "keeps absence distinct from a package record" do
      expect(record.root_package).to be_nil
    end
  end
end
