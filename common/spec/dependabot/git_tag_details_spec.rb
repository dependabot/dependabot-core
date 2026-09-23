# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/git_tag_details"

RSpec.describe Dependabot::GitTagDetails do
  let(:version) { Gem::Version.new("1.2.3") }
  let(:details) do
    described_class.new(
      tag: "v1.2.3",
      version: version,
      commit_sha: "commit-sha",
      tag_sha: "tag-sha"
    )
  end

  it "preserves Hash compatibility and typed readers" do
    expect(details).to eq(
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
end
