# frozen_string_literal: true

require "helpers/helper_dependabot"
require_relative "spec_helper"

RSpec.describe "describe pix4_dependabot function", :pix4d do
  def fixture(*name)
    File.read(File.join("..", "docker", "spec", "fixtures", *name))
  end

  let(:fake_token) { "github_token" }
  let(:docker_cred) do
    {
      "type" => "docker_registry",
      "registry" => "registry.hub.docker.com",
      "username" => nil,
      "password" => nil
    }
  end

  let(:dependency_instance) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: [{
        requirement: nil,
        groups: [],
        file: file_name,
        source: { tag: version }
      }],
      package_manager: "docker"
    )
  end
  let(:updated_dependency_instance) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: updated_version,
      previous_version: version,
      requirements: [{
        requirement: nil,
        groups: [],
        file: file_name,
        source: { tag: updated_version }
      }],
      previous_requirements: [{
        requirement: nil,
        groups: [],
        file: file_name,
        source: { tag: version }
      }],
      package_manager: "docker"
    )
  end
  let(:dependency_file) do
    Dependabot::DependencyFile.new(name: file_name, content: fixture_file, directory: dependency_dir)
  end
  let(:github_url) { "https://api.github.com/" }

  let(:expected_commit) { "c1a68d7" }
  let(:file_name) { "public-simple.yml" }
  let(:dependency_name) { "public-image-name-1" }
  let(:version) { "1.0.7" }
  let(:updated_version) { "1.10" }
  let(:pull_request) do
    {
      number: 1,
      head: { ref: "docker-#{dependency_dir[0..-2].sub('/', '-')}-#{branch}-#{dependency_name}-#{version}" },
      html_url: "https://github.com/#{repo}/pull/1"
    }
  end

  context "happy path for concourse module" do
    let(:project_data) do
      {
        "module" => "concourse",
        "repo" => "Pix4D/test_repo",
        "branch" => "master",
        "dependency_dir" => "ci/pipelines/"
      }
    end
    let(:docker_cred) do
      {
        "type" => "docker_registry",
        "registry" => "registry.hub.docker.com",
        "username" => nil,
        "password" => nil
      }
    end
    let(:git_cred) do
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "dependabot-script",
        "password" => fake_token
      }
    end
    let(:fixture_file) { fixture("pipelines", file_name) }
    let(:dependency_dir) { project_data["dependency_dir"] }
    let(:repo) { project_data["repo"] }
    let(:branch) { project_data["branch"] }

    it "returns the correct project_path" do
      allow(self).to receive(:recursive_path).and_return([dependency_dir])
      allow(self).to receive(:fetch_files_and_commit).and_return([[dependency_file], expected_commit])
      allow(self).to receive(:fetch_dependencies).and_return([dependency_instance])
      allow(self).to receive(:checker_up_to_date).and_return(false)
      allow(self).to receive(:requirements).and_return(":own")
      allow(self).to receive(:checker_updated_dependencies).and_return([updated_dependency_instance])
      allow(self).to receive(:create_pr).and_return(pull_request)

      actual = pix4_dependabot("docker", project_data, git_cred, docker_cred)
      expect(actual).to equal("Success")
    end
  end

  context "for docker module" do
    let(:project_data) do
      {
        "module" => "docker",
        "repo" => "Pix4D/test_repo",
        "branch" => "staging",
        "dependency_dir" => "dockerfiles/"
      }
    end

    let(:github_sha) { "76abc" }
    let(:repo) { project_data["repo"] }
    let(:branch) { project_data["branch"] }
    let(:url1) { github_url + "repos/#{repo}/branches/#{branch}" }
    let(:url2) do
      github_url +
        "repos/#{repo}/git/trees/#{github_sha}?recursive=true"
    end
    let(:fixture_file) { fixture("pipelines", file_name) }
    let(:dependency_dir) { project_data["dependency_dir"] }
    let(:repo) { project_data["repo"] }
    let(:branch) { project_data["branch"] }
    before do
      stub_request(:get, url1).
        to_return(
          status: 200,
          body: { "name": branch, "commit": { "sha": github_sha } }.to_json,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url2).
        to_return(
          status: 200,
          body: { "sha": github_sha, "tree": [
            { "path": "dockerfiles/folder-1/Dockerfile" }
          ] }.to_json,
          headers: { "content-type" => "application/json" }
        )
    end

    it "when directory tree for staging branch is wanted" do
      allow(self).to receive(:fetch_files_and_commit).and_return([[dependency_file], expected_commit])
      allow(self).to receive(:fetch_dependencies).and_return([dependency_instance])
      allow(self).to receive(:checker_up_to_date).and_return(false)
      allow(self).to receive(:requirements).and_return(":own")
      allow(self).to receive(:checker_updated_dependencies).and_return([updated_dependency_instance])
      allow(self).to receive(:create_pr).and_return(pull_request)
      allow(self).to receive(:auto_merge).and_return("")

      actual = pix4_dependabot("docker", project_data, fake_token, docker_cred)
      expect(actual).to equal("Success")
    end
  end

  context "happy path for python module" do
    let(:project_data) do
      {
        "module" => "pip",
        "repo" => "Pix4D/test_repo",
        "branch" => "master",
        "dependency_dir" => "/"
      }
    end
    let(:artifactory_cred) do
      {
        "EXTRA_INDEX_URL" => "https://artifactory.test.ci.pix4d.com/artifactory/api/pypi/pix4d-pypi-local/simple",
        "username" => nil,
        "password" => nil
      }
    end
    let(:git_cred) do
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "dependabot-script",
        "password" => fake_token
      }
    end
    let(:file_name) { "base_requirements.txt" }
    let(:fixture_file) do
      File.read(File.join("..", "python", "spec", "fixtures", "requirements", "base_requirements.txt"))
    end
    let(:dependency_dir) { project_data["dependency_dir"] }
    let(:repo) { project_data["repo"] }
    let(:branch) { project_data["branch"] }
    let(:dependency_name) { "requests" }
    let(:dependency_instance) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: "2.18.4",
        requirements: [{
          requirement: "==2.18.4",
          groups: ["dependencies"],
          file: file_name,
          source: nil
        }],
        package_manager: "pip"
      )
    end
    let(:updated_dependency_instance) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: "2.25.1",
        previous_version: "2.18.4",
        requirements: [{
          requirement: "==2.25.1",
          groups: ["dependencies"],
          file: file_name,
          source: nil
        }],
        previous_requirements: [{
          requirement: "==2.18.4",
          groups: ["dependencies"],
          file: file_name,
          source: nil
        }],
        package_manager: "pip"
      )
    end
    it "returns the correct project_path" do
      allow(self).to receive(:recursive_path).and_return([dependency_dir])
      allow(self).to receive(:fetch_files_and_commit).and_return([[dependency_file], expected_commit])
      allow(self).to receive(:fetch_dependencies).and_return([dependency_instance])
      allow(self).to receive(:checker_up_to_date).and_return(false)
      allow(self).to receive(:requirements).and_return(":own")
      allow(self).to receive(:checker_updated_dependencies).and_return([updated_dependency_instance])
      allow(self).to receive(:create_pr).and_return(pull_request)

      actual = pix4_dependabot("pip", project_data, git_cred, artifactory_cred)
      expect(actual).to equal("Success")
    end
  end
end
