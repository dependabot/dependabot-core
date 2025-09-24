# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Conda::FileFetcher do
  before(:all) { skip("Disabling Conda file fetcher tests") } # rubocop:disable RSpec/BeforeAfterAll

  it_behaves_like "a dependency file fetcher"

  describe "#files" do
    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "gocardless/bump",
        directory: directory
      )
    end
    let(:directory) { "/" }
    let(:file_fetcher_instance) do
      described_class.new(source: source, credentials: credentials)
    end
    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
    let(:url_with_directory) { File.join(url, directory) }
    let(:credentials) do
      [Dependabot::Credential.new(
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      )]
    end

    let(:json_header) { { "content-type" => "application/json" } }
    let(:repo_contents) do
      fixture("github", "contents_conda_repo.json")
    end

    before do
      allow(file_fetcher_instance).to receive_messages(commit: "sha", allow_beta_ecosystems?: true)

      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 200, body: repo_contents, headers: json_header)
    end

    context "with an environment.yml file" do
      before do
        stub_request(:get, File.join(url_with_directory, "environment.yml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_environment_yml.json"),
            headers: json_header
          )
      end

      it "fetches the environment.yml file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).to eq(["environment.yml"])
      end

      it "fetches the environment.yml with correct content" do
        expect(file_fetcher_instance.files.first.content).to include("python=3.11")
      end
    end

    context "with an environment.yaml file" do
      let(:repo_contents) do
        fixture("github", "contents_conda_yaml_repo.json")
      end

      before do
        stub_request(:get, File.join(url_with_directory, "environment.yaml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_environment_yaml.json"),
            headers: json_header
          )
      end

      it "fetches the environment.yaml file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).to eq(["environment.yaml"])
      end
    end

    context "when beta ecosystems are not allowed" do
      before do
        allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(false)
      end

      it "raises a DependencyFileNotFound error with beta message" do
        expect { file_fetcher_instance.files }
          .to raise_error(
            Dependabot::DependencyFileNotFound,
            "Conda support is currently in beta. Set ALLOW_BETA_ECOSYSTEMS=true to enable it."
          )
      end
    end

    context "when no environment files are present" do
      let(:repo_contents) do
        fixture("github", "contents_no_conda_repo.json")
      end

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "when environment file contains only non-manageable content" do
      before do
        # Mock environment.yml with non-Python packages only
        stub_request(:get, File.join(url_with_directory, "environment.yml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: {
              "content" => Base64.encode64(File.read("spec/fixtures/environment_non_python.yml")),
              "encoding" => "base64"
            }.to_json,
            headers: json_header
          )
      end

      it "raises a DependencyFileNotFound error with unsupported message" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound) do |error|
            expect(error.message).to include("This Conda environment file is not currently supported")
            expect(error.message).to include("Dependabot-Conda supports Python packages only")
          end
      end
    end

    context "when environment file contains fully qualified specifications" do
      before do
        # Mock environment.yml with fully qualified Python packages that should NOT be manageable
        fully_qualified_content = <<~YAML
          dependencies:
            - numpy=1.26.4=py310h5f9d8c6_0
            - requests=2.31.0=py310h06a4308_1
            - scipy=1.13.0=py310h5f9d8c6_0
        YAML

        stub_request(:get, File.join(url_with_directory, "environment.yml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: {
              "content" => Base64.encode64(fully_qualified_content),
              "encoding" => "base64"
            }.to_json,
            headers: json_header
          )
      end

      it "raises a DependencyFileNotFound error for fully qualified specs" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound) do |error|
            expect(error.message).to include("This Conda environment file is not currently supported")
          end
      end
    end

    context "when environment file has manageable pip dependencies" do
      before do
        # Mock environment.yml with pip section containing Python packages
        stub_request(:get, File.join(url_with_directory, "environment.yml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: {
              "content" => Base64.encode64(File.read("spec/fixtures/environment_pip_only_support.yml")),
              "encoding" => "base64"
            }.to_json,
            headers: json_header
          )
      end

      it "successfully fetches the environment file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).to eq(["environment.yml"])
      end
    end

    context "when environment file has invalid YAML" do
      before do
        # Mock environment.yml with invalid YAML content
        invalid_yaml_content = "dependencies:\n  - python=3.11\n  invalid_yaml: [\n"
        stub_request(:get, File.join(url_with_directory, "environment.yml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: {
              "content" => Base64.encode64(invalid_yaml_content),
              "encoding" => "base64"
            }.to_json,
            headers: json_header
          )
      end

      it "raises a DependencyFileNotFound error for invalid YAML" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound) do |error|
            expect(error.message).to include("This Conda environment file is not currently supported")
          end
      end
    end

    context "when environment file has nil content" do
      before do
        # Mock file with nil content
        allow(file_fetcher_instance).to receive(:fetch_file_if_present).and_return(nil)
        stub_request(:get, File.join(url_with_directory, "environment.yml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_environment_yml.json"),
            headers: json_header
          )
      end

      it "raises a DependencyFileNotFound error for nil content" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "when environment file has non-Hash parsed content" do
      before do
        # Mock environment.yml with content that parses to non-Hash
        non_hash_yaml_content = "- item1\n- item2\n"
        stub_request(:get, File.join(url_with_directory, "environment.yml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: {
              "content" => Base64.encode64(non_hash_yaml_content),
              "encoding" => "base64"
            }.to_json,
            headers: json_header
          )
      end

      it "raises a DependencyFileNotFound error for non-Hash content" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "when environment file has non-Array dependencies" do
      before do
        # Mock environment.yml with dependencies as string/hash
        non_array_deps_content = "dependencies: 'python=3.11'\n"
        stub_request(:get, File.join(url_with_directory, "environment.yml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: {
              "content" => Base64.encode64(non_array_deps_content),
              "encoding" => "base64"
            }.to_json,
            headers: json_header
          )
      end

      it "raises a DependencyFileNotFound error for non-Array dependencies" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "when environment file has empty dependencies array" do
      before do
        # Mock environment.yml with empty dependencies array
        empty_deps_content = "dependencies: []\n"
        stub_request(:get, File.join(url_with_directory, "environment.yml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: {
              "content" => Base64.encode64(empty_deps_content),
              "encoding" => "base64"
            }.to_json,
            headers: json_header
          )
      end

      it "raises a DependencyFileNotFound error for empty dependencies" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "when both .yml and .yaml files exist" do
      let(:repo_contents) do
        # Mock repo content showing both files exist
        [
          {
            "name" => "environment.yml",
            "type" => "file"
          },
          {
            "name" => "environment.yaml",
            "type" => "file"
          }
        ].to_json
      end

      before do
        stub_request(:get, File.join(url_with_directory, "environment.yml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_environment_yml.json"),
            headers: json_header
          )

        stub_request(:get, File.join(url_with_directory, "environment.yaml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_environment_yaml.json"),
            headers: json_header
          )
      end

      it "fetches both environment files" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).to contain_exactly("environment.yml", "environment.yaml")
      end
    end
  end

  describe ".required_files_in?" do
    it "returns true when environment.yml is present" do
      expect(described_class.required_files_in?(["environment.yml"])).to be(true)
    end

    it "returns true when environment.yaml is present" do
      expect(described_class.required_files_in?(["environment.yaml"])).to be(true)
    end

    it "returns true when both environment files are present" do
      expect(described_class.required_files_in?(["environment.yml", "environment.yaml"])).to be(true)
    end

    it "returns false when no environment files are present" do
      expect(described_class.required_files_in?(["package.json", "requirements.txt"])).to be(false)
    end
  end

  describe ".required_files_message" do
    it "returns appropriate message" do
      expect(described_class.required_files_message)
        .to eq("Repo must contain an environment.yml or environment.yaml file.")
    end
  end

  describe "#fully_qualified_spec?" do
    let(:file_fetcher) do
      described_class.new(
        source: Dependabot::Source.new(
          provider: "github",
          repo: "test/repo",
          directory: "/"
        ),
        credentials: []
      )
    end

    it "returns true for fully qualified specs with build string" do
      expect(file_fetcher.send(:fully_qualified_spec?, "numpy=1.21.0=py39h20f2e39_0")).to be(true)
    end

    it "returns true for fully qualified specs with simple build string" do
      expect(file_fetcher.send(:fully_qualified_spec?, "python=3.9.7=h60c2a47_0")).to be(true)
    end

    it "returns false for package name only" do
      expect(file_fetcher.send(:fully_qualified_spec?, "numpy")).to be(false)
    end

    it "returns false for specs with only one equals sign" do
      expect(file_fetcher.send(:fully_qualified_spec?, "numpy=1.21.0")).to be(false)
    end

    it "returns false for specs with empty build string" do
      expect(file_fetcher.send(:fully_qualified_spec?, "numpy=1.21.0=")).to be(false)
    end

    it "returns false for specs with invalid build string characters" do
      expect(file_fetcher.send(:fully_qualified_spec?, "numpy=1.21.0=invalid-chars!")).to be(false)
    end
  end

  describe "#environment_contains_manageable_packages?" do
    let(:file_fetcher) do
      described_class.new(
        source: Dependabot::Source.new(
          provider: "github",
          repo: "test/repo",
          directory: "/"
        ),
        credentials: []
      )
    end

    context "when environment contains git and cmake" do
      it "correctly identifies git and cmake as non-manageable" do
        file_content = <<~YAML
          dependencies:
            - git=2.30.0
            - cmake=3.20.0
        YAML

        dependency_file = instance_double(Dependabot::DependencyFile, content: file_content)
        result = file_fetcher.send(:environment_contains_manageable_packages?, dependency_file)

        expect(result).to be(false)
      end
    end

    context "when environment contains Python packages" do
      it "correctly identifies Python packages as manageable" do
        file_content = <<~YAML
          dependencies:
            - numpy=1.21.0
            - requests=2.25.1
        YAML

        dependency_file = instance_double(Dependabot::DependencyFile, content: file_content)
        result = file_fetcher.send(:environment_contains_manageable_packages?, dependency_file)

        expect(result).to be(true)
      end
    end

    context "when environment has pip section with Python packages" do
      it "correctly identifies pip Python packages as manageable" do
        file_content = <<~YAML
          dependencies:
            - git=2.30.0
            - pip:
              - numpy==1.21.0
              - requests>=2.25.1
        YAML

        dependency_file = instance_double(Dependabot::DependencyFile, content: file_content)
        result = file_fetcher.send(:environment_contains_manageable_packages?, dependency_file)

        expect(result).to be(true)
      end
    end

    context "when environment has pip section with non-Python packages" do
      it "correctly identifies pip non-Python packages as non-manageable" do
        file_content = <<~YAML
          dependencies:
            - git=2.30.0
            - pip:
              - git==2.30.0
              - cmake>=3.20.0
        YAML

        dependency_file = instance_double(Dependabot::DependencyFile, content: file_content)
        result = file_fetcher.send(:environment_contains_manageable_packages?, dependency_file)

        expect(result).to be(false)
      end
    end

    context "when environment contains fully qualified Python packages" do
      it "correctly identifies fully qualified specs as non-manageable" do
        file_content = <<~YAML
          dependencies:
            - numpy=1.21.0=py39h20f2e39_0
            - requests=2.25.1=py39_0
        YAML

        dependency_file = instance_double(Dependabot::DependencyFile, content: file_content)
        result = file_fetcher.send(:environment_contains_manageable_packages?, dependency_file)

        expect(result).to be(false)
      end
    end
  end
end
