# frozen_string_literal: true

require "helpers/auto_merge"
require_relative "spec_helper"

RSpec.describe "auto_merge", :pix4d do
  context "using a docker feature_package" do
    let(:github_url) { "https://api.github.com/" }
    let(:url1) do
      github_url +
        "repos/#{project_path}/pulls/#{pr_number}/merge"
    end
    let(:project_path) { "Pix4D/dependabot" }
    let(:pr_number) { "101" }

    before do
      stub_request(:put, url1).
        to_return(
          status: 200,
          body: { merged: true }.to_json,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url1).
        to_return(
          status: 404
        )
    end

    it "raises if the PR is not merged correctly" do
      expect do
        auto_merge(pr_number, "feature-branch", project_path, "token")
      end.to raise_error(RuntimeError, "The PR was not merged correctly")
    end
  end

  context "using a docker feature_package" do
    let(:github_url) { "https://api.github.com/" }
    let(:url1) do
      github_url +
        "repos/#{project_path}/pulls/#{pr_number}/merge"
    end
    let(:url2) do
      github_url +
        "repos/#{project_path}/git/refs/heads/#{pr_branch}"
    end
    let(:project_path) { "Pix4D/dependabot" }
    let(:pr_number) { "101" }
    let(:pr_branch) { "feature-branch" }

    before do
      stub_request(:put, url1).
        to_return(
          status: 200,
          body: { merged: true }.to_json,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url1).
        to_return(
          status: 204
        )
      stub_request(:delete, url2).
        to_return(
          status: 422
        )
    end

    it "returns nil if the branch was already deleted" do
      expect(auto_merge(pr_number, pr_branch, project_path, "token")).
        to be_nil
    end
  end
end
