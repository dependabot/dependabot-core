# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Conda::FileFetcher do
  let(:url) { "https://api.github.com/repos/example/repo/contents/" }
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
  let(:file_fetcher) { described_class.new(source: source, credentials: credentials) }
  let(:directory) { "/" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/repo",
      directory: directory
    )
  end

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    it "returns true when environment.yml is present" do
      expect(described_class.required_files_in?(["environment.yml"])).to be true
    end

    it "returns true when environment.yaml is present" do
      expect(described_class.required_files_in?(["environment.yaml"])).to be true
    end

    it "returns true when both files are present" do
      expect(described_class.required_files_in?(["environment.yml", "environment.yaml"])).to be true
    end

    it "returns false when no environment files are present" do
      expect(described_class.required_files_in?(["requirements.txt", "setup.py"])).to be false
    end
  end

  describe ".required_files_message" do
    it "returns appropriate message" do
      expect(described_class.required_files_message).to eq(
        "Repo must contain an environment.yml or environment.yaml file."
      )
    end
  end

  describe "#fetch_files" do
    subject(:files) { file_fetcher.fetch_files }

    context "with beta ecosystems disabled" do
      before do
        allow(file_fetcher).to receive(:allow_beta_ecosystems?).and_return(false)
      end

      it "raises error with beta message" do
        expect { files }.to raise_error(Dependabot::DependencyFileNotFound) do |error|
          expect(error.message).to include("beta")
          expect(error.message).to include("ALLOW_BETA_ECOSYSTEMS")
        end
      end
    end

    context "with beta ecosystems enabled" do
      before do
        allow(file_fetcher).to receive_messages(allow_beta_ecosystems?: true, commit: "sha")
        stub_request(:get, url + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: repo_contents_json,
            headers: { "content-type" => "application/json" }
          )
      end

      context "when environment.yml exists with simple conda packages" do
        let(:repo_contents_json) do
          JSON.dump(
            [{
              "name" => "environment.yml",
              "type" => "file",
              "size" => 100
            }]
          )
        end

        before do
          stub_request(:get, url + "environment.yml?ref=sha")
            .to_return(
              status: 200,
              body: fixture("github", "contents_environment_yml.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches environment.yml" do
          expect(files.count).to eq(1)
          expect(files.first.name).to eq("environment.yml")
        end

        it "returns DependencyFile objects" do
          expect(files.first).to be_a(Dependabot::DependencyFile)
        end
      end

      context "when environment.yaml exists" do
        let(:repo_contents_json) do
          JSON.dump(
            [{
              "name" => "environment.yaml",
              "type" => "file"
            }]
          )
        end

        before do
          stub_request(:get, url + "environment.yaml?ref=sha")
            .to_return(
              status: 200,
              body: fixture("github", "contents_environment_yaml.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches environment.yaml" do
          expect(files.count).to eq(1)
          expect(files.first.name).to eq("environment.yaml")
        end
      end

      context "when both environment files exist" do
        let(:repo_contents_json) do
          JSON.dump(
            [
              { "name" => "environment.yml", "type" => "file" },
              { "name" => "environment.yaml", "type" => "file" }
            ]
          )
        end

        before do
          stub_request(:get, url + "environment.yml?ref=sha")
            .to_return(
              status: 200,
              body: fixture("github", "contents_environment_yml.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches environment.yml (priority)" do
          expect(files.count).to eq(1)
          expect(files.first.name).to eq("environment.yml")
        end
      end

      context "when no environment file exists" do
        let(:repo_contents_json) { JSON.dump([{ "name" => "README.md", "type" => "file" }]) }

        it "raises DependencyFileNotFound" do
          expect { files }.to raise_error(Dependabot::DependencyFileNotFound)
        end
      end

      context "when environment file has no manageable packages" do
        let(:repo_contents_json) do
          JSON.dump([{ "name" => "environment.yml", "type" => "file" }])
        end

        before do
          stub_request(:get, url + "environment.yml?ref=sha")
            .to_return(
              status: 200,
              body: JSON.dump(
                {
                  "type" => "file",
                  "encoding" => "base64",
                  "content" => Base64.encode64(unsupported_content)
                }
              ),
              headers: { "content-type" => "application/json" }
            )
        end

        context "with only fully qualified packages" do
          let(:unsupported_content) do
            <<~YAML
              dependencies:
                - python=3.9.7=h60c2a47_0_cpython
                - numpy=1.21.0=py39h20f2e39_0
            YAML
          end

          it "raises error with specific fully qualified message" do
            expect { files }.to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.message).to include("fully qualified package specifications")
            end
          end
        end

        context "with empty dependencies" do
          let(:unsupported_content) do
            <<~YAML
              dependencies: []
            YAML
          end

          it "raises error with specific no dependencies message" do
            expect { files }.to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.message).to include("no dependencies to manage")
            end
          end
        end

        context "with missing dependencies key" do
          let(:unsupported_content) do
            <<~YAML
              name: myenv
              channels:
                - conda-forge
            YAML
          end

          it "raises error with specific no dependencies message" do
            expect { files }.to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.message).to include("no dependencies to manage")
            end
          end
        end

        context "with invalid YAML" do
          let(:unsupported_content) { "invalid: yaml: [unclosed" }

          it "raises error with specific YAML syntax message" do
            expect { files }.to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.message).to include("invalid YAML syntax")
            end
          end
        end

        context "with non-Hash YAML" do
          let(:unsupported_content) { "- just\n- a\n- list" }

          it "raises error with specific YAML syntax message" do
            expect { files }.to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.message).to include("invalid YAML syntax")
            end
          end
        end

        context "with non-Array dependencies" do
          let(:unsupported_content) do
            <<~YAML
              dependencies: "not an array"
            YAML
          end

          it "raises error with specific no dependencies message" do
            expect { files }.to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.message).to include("no dependencies to manage")
            end
          end
        end
      end

      context "when environment file has manageable packages" do
        let(:repo_contents_json) do
          JSON.dump([{ "name" => "environment.yml", "type" => "file" }])
        end

        before do
          stub_request(:get, url + "environment.yml?ref=sha")
            .to_return(
              status: 200,
              body: JSON.dump(
                {
                  "type" => "file",
                  "encoding" => "base64",
                  "content" => Base64.encode64(valid_content)
                }
              ),
              headers: { "content-type" => "application/json" }
            )
        end

        context "with simple conda packages" do
          let(:valid_content) do
            <<~YAML
              dependencies:
                - python=3.11
                - numpy>=1.24.0
                - r-base=4.0
            YAML
          end

          it "successfully fetches the file" do
            expect(files.count).to eq(1)
            expect(files.first.name).to eq("environment.yml")
          end
        end

        context "with pip packages" do
          let(:valid_content) do
            <<~YAML
              dependencies:
                - python=3.11
                - pip:
                  - requests>=2.28.0
            YAML
          end

          it "successfully fetches the file" do
            expect(files.count).to eq(1)
          end
        end

        context "with only pip packages (no conda)" do
          let(:valid_content) do
            <<~YAML
              dependencies:
                - pip:
                  - requests>=2.28.0
                  - flask>=3.0
            YAML
          end

          it "successfully fetches the file" do
            expect(files.count).to eq(1)
          end
        end

        context "with mixed fully-qualified and simple packages" do
          let(:valid_content) do
            <<~YAML
              dependencies:
                - numpy=1.24.0
                - python=3.9.7=h60c2a47_0_cpython
            YAML
          end

          it "successfully fetches the file (has at least one simple spec)" do
            expect(files.count).to eq(1)
          end
        end
      end
    end
  end

  describe "#fully_qualified_spec?" do
    it "returns true for fully qualified specs with build string" do
      expect(file_fetcher.send(:fully_qualified_spec?, "python=3.9.7=h60c2a47_0_cpython")).to be true
    end

    it "returns true for fully qualified specs with simple build string" do
      expect(file_fetcher.send(:fully_qualified_spec?, "numpy=1.21.0=py39h20f2e39_0")).to be true
    end

    it "returns false for package name only" do
      expect(file_fetcher.send(:fully_qualified_spec?, "numpy")).to be false
    end

    it "returns false for specs with only one equals sign" do
      expect(file_fetcher.send(:fully_qualified_spec?, "numpy=1.21.0")).to be false
    end

    it "returns false for pin operator with ==" do
      expect(file_fetcher.send(:fully_qualified_spec?, "numpy==1.21.0")).to be false
    end

    it "returns false for bracket syntax" do
      expect(file_fetcher.send(:fully_qualified_spec?, "numpy[version='>=1.21']")).to be false
    end

    it "returns false for comparison operators" do
      expect(file_fetcher.send(:fully_qualified_spec?, "numpy>=1.21.0")).to be false
    end
  end

  describe "#manageable_packages?" do
    it "returns true when there are simple conda packages" do
      deps = ["python=3.11", "numpy>=1.24.0"]
      expect(file_fetcher.send(:manageable_packages?, deps)).to be true
    end

    it "returns true when there are pip packages" do
      deps = [{ "pip" => ["requests>=2.28.0"] }]
      expect(file_fetcher.send(:manageable_packages?, deps)).to be true
    end

    it "returns true when there are both" do
      deps = ["python=3.11", { "pip" => ["requests>=2.28.0"] }]
      expect(file_fetcher.send(:manageable_packages?, deps)).to be true
    end

    it "returns false when all packages are fully qualified" do
      deps = ["python=3.9.7=h60c2a47_0_cpython", "numpy=1.21.0=py39h20f2e39_0"]
      expect(file_fetcher.send(:manageable_packages?, deps)).to be false
    end

    it "returns false for empty array" do
      expect(file_fetcher.send(:manageable_packages?, [])).to be false
    end

    it "returns false for non-array input" do
      expect(file_fetcher.send(:manageable_packages?, "not an array")).to be false
    end
  end

  private

  def fixture(*name)
    File.read(File.join(__dir__, "../../fixtures", File.join(*name)))
  end
end
