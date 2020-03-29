# frozen_string_literal: true

require "dependabot/path_level"
require "spec_helper"

RSpec.describe "recursive_path", :pix4d do
  context "using a concourse feature_package" do
    it "returns the correct project_path" do
      expect(recursive_path(
               "concourse",
               "Pix4D/dependabot",
               "ci/pipelines",
               "token"
             )).to eq(["ci/pipelines"])
    end
  end

  context "using a docker feature_package" do
    let(:github_url) { "https://api.github.com/" }
    let(:url_1) { github_url + "repos/#{project_path}/branches/master" }
    let(:url_2) do
      github_url +
        "repos/#{project_path}/git/trees/#{github_sha}?recursive=true"
    end
    let(:project_path) { "Pix4D/dependabot" }
    let(:dependency_dir) { "dockerfiles" }
    let(:github_sha) { "76abc" }

    before do
      stub_request(:get, url_1).
        to_return(
          status: 200,
          body: { "name": "master", "commit": { "sha": github_sha } }.to_json,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url_2).
        to_return(
          status: 200,
          body: { "sha": github_sha, "tree": [
            { "path": "dockerfiles/folder-1/Dockerfile" },
            { "path": "dockerfiles/folder-2/Dockerfile" },
            { "path": "dockerfiles/folder-2/code.py" },
            { "path": "ci/pipeline-template.ymls" }
          ] }.to_json,
          headers: { "content-type" => "application/json" }
        )
    end

    it "returns the correct project_path" do
      expect(recursive_path("docker", project_path, dependency_dir, "token")).
        to eq(["dockerfiles/folder-1", "dockerfiles/folder-2"])
    end
  end

  context "using a docker feature_package" do
    let(:github_url) { "https://api.github.com/" }
    let(:url_1) { github_url + "repos/#{project_path}/branches/master" }
    let(:project_path) { "Pix4D/non-existing" }

    before do
      stub_request(:get, url_1).
        to_return(
          status: 404,
          body: { "message": "not found" }.to_json,
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a correct error (repo not found)" do
      expect { recursive_path("docker", project_path, "path", "token") }.
        to raise_error(Octokit::NotFound, "GET #{url_1}: 404 - not found")
    end
  end

  context "using a docker feature_package" do
    let(:github_url) { "https://api.github.com/" }
    let(:url_1) { github_url + "repos/#{project_path}/branches/master" }
    let(:url_2) do
      github_url +
        "repos/#{project_path}/git/trees/#{github_sha}?recursive=true"
    end
    let(:project_path) { "Pix4D/dependabot" }
    let(:dependency_dir) { "dockerfiles" }
    let(:github_sha) { "76abc" }

    before do
      stub_request(:get, url_1).
        to_return(
          status: 200,
          body: { "name": "master", "commit": { "sha": github_sha } }.to_json,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url_2).
        to_return(
          status: 404,
          body: { "message": "not found" }.to_json,
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a correct error (tree not found)" do
      expect { recursive_path("docker", project_path, "path", "token") }.
        to raise_error(Octokit::NotFound, "GET #{url_2}: 404 - not found")
    end
  end
end
