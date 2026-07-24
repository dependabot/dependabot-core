# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/powershell/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Powershell::FileFetcher do
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { github_url + "repos/example/repo/contents/" }
  let(:github_url) { "https://api.github.com/" }
  let(:directory) { "/" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/repo",
      directory: directory
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: nil
    )
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    it "returns true when a .psd1 manifest is present" do
      expect(described_class.required_files_in?(["MyModule.psd1"])).to be true
    end

    it "returns true when a .ps1 script is present" do
      expect(described_class.required_files_in?(["Deploy.ps1"])).to be true
    end

    it "returns true when a .psm1 script is present" do
      expect(described_class.required_files_in?(["MyScriptModule.psm1"])).to be true
    end

    it "returns false when no relevant files are present" do
      expect(described_class.required_files_in?(["README.md", "azure-pipelines.yml"])).to be false
    end
  end

  describe ".required_files_message" do
    it "returns an appropriate message" do
      expect(described_class.required_files_message).to eq(
        "Repo must contain a PowerShell module manifest (.psd1) file, or a .ps1/.psm1 script " \
        "with a '#Requires -Modules' directive."
      )
    end
  end

  describe "#fetch_files" do
    subject(:files) { file_fetcher_instance.fetch_files }

    before do
      allow(file_fetcher_instance).to receive_messages(allow_beta_ecosystems?: true, commit: "sha")
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: repo_contents_json,
          headers: { "content-type" => "application/json" }
        )
    end

    def stub_content(name, content)
      stub_request(:get, url + "#{name}?ref=sha")
        .to_return(
          status: 200,
          body: JSON.dump(
            {
              "type" => "file",
              "encoding" => "base64",
              "content" => Base64.encode64(content)
            }
          ),
          headers: { "content-type" => "application/json" }
        )
    end

    context "when a .psd1 manifest exists" do
      let(:repo_contents_json) do
        JSON.dump([{ "name" => "MyModule.psd1", "type" => "file" }])
      end

      before { stub_content("MyModule.psd1", fixture("psd1", "basic_manifest.psd1")) }

      it "fetches the manifest file" do
        expect(files.count).to eq(1)
        expect(files.first.name).to eq("MyModule.psd1")
      end

      it "returns DependencyFile objects" do
        expect(files.first).to be_a(Dependabot::DependencyFile)
      end
    end

    context "when a .ps1 script with #Requires -Modules exists" do
      let(:repo_contents_json) do
        JSON.dump([{ "name" => "Deploy.ps1", "type" => "file" }])
      end

      before { stub_content("Deploy.ps1", fixture("ps1", "requires_script.ps1")) }

      it "fetches the script file" do
        expect(files.count).to eq(1)
        expect(files.first.name).to eq("Deploy.ps1")
      end
    end

    context "when a .ps1 script without #Requires -Modules exists" do
      let(:repo_contents_json) do
        JSON.dump([{ "name" => "NoRequires.ps1", "type" => "file" }])
      end

      before { stub_content("NoRequires.ps1", fixture("ps1", "no_requires_script.ps1")) }

      it "raises DependencyFileNotFound" do
        expect { files }.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "when a .psm1 script with #Requires -Modules exists" do
      let(:repo_contents_json) do
        JSON.dump([{ "name" => "MyScriptModule.psm1", "type" => "file" }])
      end

      before { stub_content("MyScriptModule.psm1", fixture("psm1", "requires_module.psm1")) }

      it "fetches the script module file" do
        expect(files.count).to eq(1)
        expect(files.first.name).to eq("MyScriptModule.psm1")
      end
    end

    context "when no relevant files exist" do
      let(:repo_contents_json) { JSON.dump([{ "name" => "README.md", "type" => "file" }]) }

      it "raises DependencyFileNotFound" do
        expect { files }.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "when beta ecosystems are not enabled" do
      before { allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(false) }

      let(:repo_contents_json) do
        JSON.dump([{ "name" => "MyModule.psd1", "type" => "file" }])
      end

      it "raises DependencyFileNotFound" do
        expect { files }.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end
end
