# frozen_string_literal: true

require_relative "dependabot-main"

# rubocop:disable Metrics/BlockLength
RSpec.describe "main function", :pix4d do
  def fixture(*name)
    File.read(File.join("spec", "fixtures", *name))
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

    let(:fixture_file) { fixture("pipelines", file_name) }
    let(:dependency_dir) { project_data["dependency_dir"] }
    let(:repo) { project_data["repo"] }
    let(:branch) { project_data["branch"] }

    it "returns the correct project_path" do
      allow(self).to receive(:recursive_path).and_return([dependency_dir])
      allow(self).to receive(:file_fetcher).and_return([[dependency_file], expected_commit])
      allow(self).to receive(:file_parser).and_return([dependency_instance])
      allow(self).to receive(:checker_up_to_date).and_return(false)
      allow(self).to receive(:requirements).and_return(":own")
      allow(self).to receive(:checker_updated_dependencies).and_return([updated_dependency_instance])
      allow(self).to receive(:pr_creator).and_return(pull_request)

      actual = main(project_data, fake_token, docker_cred)
      expect(actual).to equal("Success")
    end
  end
end
# rubocop:enable Metrics/BlockLength
