# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/github_release"

RSpec.describe Dependabot::Clients::GithubRelease do
  describe ".from_resource" do
    subject(:release) { described_class.from_resource(resource) }

    let(:agent) { instance_double(Sawyer::Agent) }
    let(:resource) { Sawyer::Resource.new(agent, data) }

    before do
      allow(agent).to receive(:parse_links) { |value| [value, {}] }
    end

    context "with a valid release" do
      let(:published_at) { Time.utc(2026, 7, 1, 12) }
      let(:data) do
        {
          id: 123,
          name: "Version 1.2.3",
          tag_name: "v1.2.3",
          body: "Release notes",
          html_url: "https://github.com/dependabot/dependabot-core/releases/tag/v1.2.3",
          prerelease: true,
          published_at: published_at
        }
      end

      it "parses the known fields" do
        expect(release).to have_attributes(
          id: 123,
          name: "Version 1.2.3",
          tag_name: "v1.2.3",
          body: "Release notes",
          html_url: "https://github.com/dependabot/dependabot-core/releases/tag/v1.2.3",
          prerelease: true,
          published_at: published_at
        )
      end
    end

    context "with a timestamp string" do
      let(:data) { { tag_name: "v1.2.3", published_at: "2026-07-01T12:00:00Z" } }

      it "parses published_at" do
        expect(release&.published_at).to eq(Time.utc(2026, 7, 1, 12))
      end
    end

    context "without a string tag name" do
      let(:data) { { tag_name: nil, prerelease: true } }

      it { is_expected.to be_nil }
    end

    context "with malformed optional values" do
      let(:data) do
        {
          id: "123",
          tag_name: "v1.2.3",
          name: 1,
          body: [],
          html_url: {},
          prerelease: "true",
          published_at: "not a timestamp"
        }
      end

      it "drops them" do
        expect(release).to have_attributes(
          id: nil,
          name: nil,
          tag_name: "v1.2.3",
          body: nil,
          html_url: nil,
          prerelease: false,
          published_at: nil
        )
      end
    end
  end
end
