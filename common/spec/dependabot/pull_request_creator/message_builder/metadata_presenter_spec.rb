# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request_creator/message_builder/metadata_presenter"

namespace = Dependabot::PullRequestCreator::MessageBuilder
RSpec.describe namespace::MetadataPresenter do
  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "dummy",
      requirements:
        [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
      previous_requirements:
        [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
    )
  end

  let(:metadata_finder) do
    instance_double(Dependabot::MetadataFinders::Base,
                    changelog_url: "http://localhost/changelog.md",
                    changelog_text: "",
                    commits_url: "http://localhost/commits",
                    commits: [],
                    maintainer_changes: "",
                    releases_url: "http://localhost/releases",
                    releases_text: "",
                    source_url: "http://localhost/",
                    upgrade_guide_url: "http://localhost/upgrade.md",
                    upgrade_guide_text: "")
  end

  let(:vulnerabilities_fixed) { [] }

  let(:github_redirection_service) { "redirect.github.com" }

  subject(:presenter) do
    described_class.new(
      dependency: dependency,
      source: source,
      metadata_finder: metadata_finder,
      vulnerabilities_fixed: vulnerabilities_fixed,
      github_redirection_service: github_redirection_service
    )
  end

  describe "#to_s" do
    context "with a changelog that requires truncation" do
      before do
        allow(metadata_finder).
          to receive(:changelog_text) { fixture("raw", "changelog.md") }
      end

      it "adds a truncation notice" do
        expect(presenter.to_s).to include("(truncated)")
      end

      it "removes all content after the 50th line" do
        expect(presenter.to_s).not_to include("## 1.0.0 - June 11, 2014")
      end
    end
  end
end
