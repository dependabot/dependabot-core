# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/workspace_lockfile"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::WorkspaceLockfile do
  extend T::Sig

  sig { returns(T.nilable(String)) }
  subject(:content) do
    described_class.new(
      lockfile: lockfile,
      original_lockfile: original_lockfile,
      manifest_file: manifest
    ).cleaned_content(indent: "  ")
  end

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::DependencyFile) }
  let(:lockfile) { Dependabot::DependencyFile.new(name: "package-lock.json", content: data.to_json) }

  sig { returns(T::Hash[String, Object]) }
  let(:data) do
    {
      "lockfileVersion" => 3,
      "packages" => {
        "" => {
          "dependencies" => { "kept" => "^2", "second" => "^2", "spurious" => "^1" },
          "devDependencies" => { "spurious" => "^1" },
          "peerDependencies" => { "peer" => "^2", "spurious" => "^1" },
          "future" => [false]
        },
        "node_modules/existing" => { "version" => "2" }
      },
      "future" => { "opaque" => true }
    }
  end

  sig { returns(Dependabot::DependencyFile) }
  let(:original_lockfile) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: {
        "packages" => {
          "node_modules/missing" => { "optional" => true, "peer" => true, "version" => "1", "future" => false },
          "node_modules/existing" => { "optional" => true, "peer" => true, "version" => "1" },
          "node_modules/ordinary" => { "version" => "1" }
        }
      }.to_json
    )
  end

  sig { returns(Dependabot::DependencyFile) }
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: {
        "dependencies" => { "second" => false, "kept" => false },
        "peerDependencies" => { "peer" => "^1" }
      }.to_json
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  it "cleans root requirements and restores only missing optional peers without losing opaque fields" do
    parsed = JSON.parse(T.must(content))

    expect(parsed["packages"][""]).to eq(
      "dependencies" => { "kept" => "^2", "second" => "^2" },
      "peerDependencies" => { "peer" => "^2" },
      "future" => [false]
    )
    expect(parsed["packages"][""]["dependencies"].keys).to eq(%w(kept second))
    expect(parsed["packages"]["node_modules/missing"])
      .to eq("optional" => true, "peer" => true, "version" => "1", "future" => false)
    expect(parsed["packages"]["node_modules/existing"]).to eq("version" => "2")
    expect(parsed["packages"]).not_to have_key("node_modules/ordinary")
    expect(parsed["future"]).to eq("opaque" => true)
    expect(content).to end_with("}\n")
  end

  context "with nothing to change" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(T::Hash[String, Object]) }
    let(:data) { { "packages" => { "" => { "dependencies" => { "kept" => "^2" } } } } }

    sig { returns(Dependabot::DependencyFile) }
    let(:original_lockfile) { lockfile }
    # rubocop:enable RSpec/ScatteredLet

    it "does not request a rewrite" do
      expect(content).to be_nil
    end
  end

  context "with a legacy lockfile" do
    sig { returns(T::Hash[String, Object]) }
    let(:data) { { "dependencies" => { "kept" => { "version" => "2" } } } }

    it "does not invent a packages table" do
      expect(content).to be_nil
    end
  end

  context "with malformed consumed root requirements" do
    sig { returns(T::Hash[String, Object]) }
    let(:data) { { "packages" => { "" => { "dependencies" => [] } } } }

    it "reports the lockfile field instead of partially editing it" do
      expect { content }.to raise_error(Dependabot::DependencyFileNotParseable, /dependencies/)
    end
  end
end
