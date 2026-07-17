# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/git_commit_checker/github_release"

RSpec.describe Dependabot::GitCommitChecker::GitHubRelease do
  describe ".from_resource" do
    subject(:release) { described_class.from_resource(resource) }

    let(:agent) { instance_double(Sawyer::Agent, parse_links: [data, {}]) }
    let(:resource) { Sawyer::Resource.new(agent, data) }

    context "with a valid release" do
      let(:data) { { tag_name: "v1.2.3", prerelease: true } }

      it "parses the known fields" do
        expect(release).to have_attributes(tag_name: "v1.2.3", prerelease: true)
      end
    end

    context "without a string tag name" do
      let(:data) { { tag_name: nil, prerelease: true } }

      it { is_expected.to be_nil }
    end

    context "with a non-boolean prerelease value" do
      let(:data) { { tag_name: "v1.2.3", prerelease: "true" } }

      it "treats the release as stable" do
        expect(release).to have_attributes(tag_name: "v1.2.3", prerelease: false)
      end
    end
  end
end
