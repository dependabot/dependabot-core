# frozen_string_literal: true

require "helpers/helper_dependabot"
require_relative "spec_helper"

def fixture(package_manager, *name)
  File.read(File.join("..", package_manager, "spec", "fixtures", *name))
end

RSpec.describe "describe pix4_dependabot function", :pix4d do
  let(:github_url) { "https://api.github.com/" }
  let(:fake_token) { "github_token" }
  let(:expected_commit) { "c1a68d7" }
  let(:git_cred) do
    {
      "type" => "git_source",
      "host" => "github.com",
      "username" => "dependabot-script",
      "password" => fake_token
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
  let(:artifactory_cred) do
    {
      "EXTRA_INDEX_URL" => "https://artifactory.test.ci.pix4d.com/artifactory/api/pypi/pix4d-pypi-local/simple",
      "username" => nil,
      "password" => nil
    }
  end
  let(:dependency_file) do
    Dependabot::DependencyFile.new(name: file_name, content: fixture_file, directory: dependency_dir)
  end
  let(:dependency_dir) { project_data["dependency_dir"] }
  let(:repo) { project_data["repo"] }
  let(:branch) { project_data["branch"] }

  describe "using Docker package manager" do
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

    let(:file_name) { "public-simple.yml" }
    let(:fixture_file) { fixture("docker", "pipelines", file_name) }

    context "for concourse module" do
      let(:project_data) do
        {
          "module" => "concourse",
          "repo" => "Pix4D/test_repo",
          "branch" => "master",
          "dependency_dir" => "ci/pipelines/"
        }
      end

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
      let(:url1) { github_url + "repos/#{repo}/branches/#{branch}" }
      let(:url2) do
        github_url +
          "repos/#{repo}/git/trees/#{github_sha}?recursive=true"
      end
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
  end

  describe "using Python package manager" do
    let(:dependency_instance) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: version,
        requirements: [{
          requirement: "==#{version}",
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
        version: updated_version,
        previous_version: version,
        requirements: [{
          requirement: "==#{updated_version}",
          groups: ["dependencies"],
          file: file_name,
          source: nil
        }],
        previous_requirements: [{
          requirement: "==#{version}",
          groups: ["dependencies"],
          file: file_name,
          source: nil
        }],
        package_manager: "pip"
      )
    end
    let(:project_data) do
      {
        "module" => "pip",
        "repo" => "Pix4D/test_repo",
        "branch" => "master",
        "dependency_dir" => "requirement"
      }
    end
    let(:pull_request) do
      {
        number: 1,
        head: { ref: "python-#{dependency_dir.sub('/', '-')}-#{branch}-#{dependency_name}-#{version}" },
        html_url: "https://github.com/#{repo}/pull/1"
      }
    end
    let(:file_name) { "base_requirements.txt" }
    let(:fixture_file) { fixture("python", "requirements", file_name) }

    context "for a single dependency" do
      let(:dependency_name) { "requests" }
      let(:version) { "2.18.4" }
      let(:updated_version) { "2.25.1" }
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

    context "for multiple dependencies" do
      let(:file_name) { "multi_dependencies.txt" }
      let(:file_name2) { "multi_dependencies_update.txt" }
      let(:dependency_file2) do
        Dependabot::DependencyFile.new(name: file_name2, content: fixture_file, directory: dependency_dir)
      end
      let(:dependency_name) { "requests" }
      let(:version) { "2.18.4" }
      let(:updated_version) { "2.25.1" }
      let(:dependency_name2) { "luigi" }
      let(:version2) { "1.2.0" }
      let(:updated_version2) { "1.5.4" }
      let(:dependency_instance2) do
        Dependabot::Dependency.new(
          name: dependency_name2,
          version: version2,
          requirements: [{
            requirement: "==#{version2}",
            groups: ["dependencies"],
            file: file_name,
            source: nil
          }],
          package_manager: "pip"
        )
      end
      let(:updated_dependency_instance2) do
        Dependabot::Dependency.new(
          name: dependency_name2,
          version: updated_version2,
          previous_version: version2,
          requirements: [{
            requirement: "==#{updated_version2}",
            groups: ["dependencies"],
            file: file_name,
            source: nil
          }],
          previous_requirements: [{
            requirement: "==#{version2}",
            groups: ["dependencies"],
            file: file_name,
            source: nil
          }],
          package_manager: "pip"
        )
      end
      it "returns the correct project_path" do
        allow(self).to receive(:recursive_path).and_return([dependency_dir])
        allow(self).to receive(:fetch_files_and_commit).and_return([[dependency_file], expected_commit],
                                                                   [[dependency_file2], expected_commit])
        allow(self).to receive(:fetch_dependencies).and_return([dependency_instance, dependency_instance2])
        allow(self).to receive(:checker_up_to_date).and_return(false, false)
        allow(self).to receive(:requirements).and_return(":own", ":own")
        allow(self).to receive(:checker_updated_dependencies).and_return([updated_dependency_instance],
                                                                         [updated_dependency_instance2])
        allow(self).to receive(:create_pr).and_return(pull_request)

        actual = pix4_dependabot("pip", project_data, git_cred, artifactory_cred)
        expect(actual).to equal("Success")
      end
    end
  end
end
