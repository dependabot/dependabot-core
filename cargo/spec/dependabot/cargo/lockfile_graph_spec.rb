# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/lockfile_graph"

RSpec.describe Dependabot::Cargo::LockfileGraph do
  extend T::Sig

  sig { returns(Dependabot::DependencyFile) }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Cargo.lock",
      content: fixture("lockfiles", "bare_version_specified")
    )
  end

  it "returns facts for named dependency files through the native helper" do
    result = described_class.facts(snapshots: { "before" => lockfile, "after" => lockfile })

    expect(result["schema_version"]).to eq(1)
    expect(result["snapshots"]).to contain_exactly(
      hash_including(
        "name" => "before",
        "complete" => true,
        "packages" => a_kind_of(Array),
        "edges" => a_kind_of(Array)
      ),
      hash_including("name" => "after", "complete" => true, "packages" => a_kind_of(Array), "edges" => a_kind_of(Array))
    )
  end

  it "returns an incomplete snapshot for an invalid lockfile" do
    invalid = Dependabot::DependencyFile.new(name: "Cargo.lock", content: "version = 99")
    result = described_class.facts(snapshots: { "invalid" => invalid })

    expect(result["snapshots"]).to contain_exactly(
      hash_including("complete" => false, "diagnostics" => [hash_including("code" => "parse_error")])
    )
  end

  it "surfaces helper protocol failures" do
    expect { described_class.facts(snapshots: { "" => lockfile }) }
      .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /nonempty and unique/)
  end

  it "rejects dependency files without content" do
    missing = Dependabot::DependencyFile.new(name: "Cargo.lock", content: nil)

    expect { described_class.facts(snapshots: { "before" => missing }) }
      .to raise_error(ArgumentError, /Cargo.lock has no content/)
  end
end
