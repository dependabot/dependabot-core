# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/git_tag_details"

RSpec.describe Dependabot::GitTagDetails do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Gem::Version) }
  let(:version) { Gem::Version.new("1.2.3") }

  sig { returns(Dependabot::GitTagDetails) } # rubocop:disable RSpec/DescribedClass -- Signatures need concrete types.
  let(:details) do
    described_class.new(
      tag: "v1.2.3",
      version: version,
      commit_sha: "commit-sha",
      tag_sha: "tag-sha"
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  it "preserves tag metadata when serialized" do
    expect(details.to_h).to eq(
      tag: "v1.2.3",
      version: version,
      commit_sha: "commit-sha",
      tag_sha: "tag-sha"
    )
    expect(details.tag).to eq("v1.2.3")
    expect(details.version).to eq(version)
    expect(details.commit_sha).to eq("commit-sha")
    expect(details.tag_sha).to eq("tag-sha")
  end

  it "compares tag records by their values" do
    expect(details).to eq(
      described_class.new(tag: "v1.2.3", version: version, commit_sha: "commit-sha", tag_sha: "tag-sha")
    )
    expect(details).not_to eq(described_class.new(tag: "v1.2.3"))
  end

  it "preserves absent version and SHA fields when serialized" do
    expect(described_class.new(tag: "unversioned").to_h).to eq(
      tag: "unversioned",
      version: nil,
      commit_sha: nil,
      tag_sha: nil
    )
  end
end
