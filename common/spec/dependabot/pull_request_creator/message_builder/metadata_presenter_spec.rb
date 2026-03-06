# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request_creator/message_builder/metadata_presenter"

namespace = Dependabot::PullRequestCreator::MessageBuilder
RSpec.describe namespace::MetadataPresenter do
  subject(:presenter) do
    described_class.new(
      dependency: dependency,
      source: source,
      metadata_finder: metadata_finder,
      vulnerabilities_fixed: vulnerabilities_fixed,
      github_redirection_service: github_redirection_service
    )
  end

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
    instance_double(
      Dependabot::MetadataFinders::Base,
      attestation_changes: "",
      changelog_url: "http://localhost/changelog.md",
      changelog_text: "",
      commits_url: "http://localhost/commits",
      commits: [],
      install_script_changes: "",
      maintainer_changes: "",
      releases_url: "http://localhost/releases",
      releases_text: "",
      source_url: "http://localhost/",
      upgrade_guide_url: "http://localhost/upgrade.md",
      upgrade_guide_text: ""
    )
  end

  let(:vulnerabilities_fixed) { [] }

  let(:github_redirection_service) { "redirect.github.com" }

  describe "#to_s" do
    context "with a changelog that requires truncation" do
      before do
        allow(metadata_finder)
          .to receive(:changelog_text) { fixture("raw", "changelog.md") }
      end

      it "adds a truncation notice" do
        expect(presenter.to_s).to include("(truncated)")
      end

      it "removes all content after the 50th line" do
        expect(presenter.to_s).not_to include("## 1.0.0 - June 11, 2014")
      end

      context "with an azure source" do
        let(:source) { Dependabot::Source.new(provider: "azure", repo: "gc/bp") }

        it "adds a truncation notice" do
          expect(presenter.to_s).to include("(truncated)")
        end

        it "does not include a closing table fragment" do
          expect(presenter.to_s).not_to include("></tr></table>")
        end

        it "removes all content after the 50th line" do
          expect(presenter.to_s).not_to include("## 1.0.0 - June 11, 2014")
        end
      end
    end

    context "with install script changes" do
      before do
        allow(metadata_finder)
          .to receive(:install_script_changes)
          .and_return("This version adds `postinstall` script that runs during installation.")
      end

      it "includes install script changes section" do
        expect(presenter.to_s).to include("Install script changes")
        expect(presenter.to_s).to include("postinstall")
      end
    end

    context "with attestation changes" do
      before do
        allow(metadata_finder)
          .to receive(:attestation_changes)
          .and_return("This version has no provenance attestation, while the previous version (1.0.0) was attested.")
      end

      it "includes attestation changes section" do
        expect(presenter.to_s).to include("Attestation changes")
        expect(presenter.to_s).to include("provenance attestation")
      end
    end
  end
end
