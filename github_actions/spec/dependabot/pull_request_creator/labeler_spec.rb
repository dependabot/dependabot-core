# frozen_string_literal: true

require "spec_helper"

RSpec.describe Dependabot::PullRequestCreator::Labeler do
  subject(:labeler) do
    described_class.new(
      source: source,
      credentials: [],
      custom_labels: nil,
      includes_security_fixes: false,
      dependencies: [dependency],
      label_language: true,
      automerge_candidate: false
    )
  end

  let(:dependency) { Dependabot::Dependency.new(name: "dependabot/updater-action", package_manager: "github_actions", requirements: []) }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "dependabot/dependabot-core") }

  describe "#create_default_labels_if_required" do
    context "when the 'github_actions' label doesn't yet exist" do
      before do
        allow(described_class).to receive(:label_details_for_package_manager)
          .with("github_actions")
          .and_return({ colour: "000000", name: "github_actions", description: "Pull requests that update GitHub action code" })

        stub_request(:get, "https://api.github.com/repos/#{source.repo}/labels?per_page=100")
          .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate([]))
        stub_request(:post, "https://api.github.com/repos/#{source.repo}/labels")
          .to_return( status: 201, headers: { "Content-Type" => "application/json" }, body: JSON.generate({ id: 1, name: "github_actions", color: "000000" }))
      end

      it "creates a label" do
        labeler.create_default_labels_if_required

        expect(WebMock).to have_requested(:post, "https://api.github.com/repos/#{source.repo}/labels")
          .with(body: {
            name: "github_actions",
            color: "000000",
            description: "Pull requests that update GitHub action code"
          })
        expect(labeler.labels_for_pr).to include("dependencies")
      end
    end
  end
end
