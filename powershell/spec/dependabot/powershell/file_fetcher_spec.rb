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
        "with a '#Requires -Modules' directive or 'using module' statement."
      )
    end
  end

  describe "#fetch_files" do
    subject(:files) { file_fetcher_instance.fetch_files }

    before do
      allow(file_fetcher_instance).to receive_messages(allow_beta_ecosystems?: true, commit: "sha")
      stub_request(:get, directory_contents_url)
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: repo_contents_json,
          headers: { "content-type" => "application/json" }
        )
    end

    def stub_content(name, content)
      path = [directory.delete_prefix("/"), name].reject(&:empty?).join("/")
      stub_request(:get, url + "#{path}?ref=sha")
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

    let(:directory_contents_url) do
      url + "#{directory.delete_prefix('/')}?ref=sha"
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

    context "when a .ps1 script with using module exists" do
      let(:repo_contents_json) do
        JSON.dump([{ "name" => "UsingModule.ps1", "type" => "file" }])
      end

      before { stub_content("UsingModule.ps1", fixture("ps1", "using_module_script.ps1")) }

      it "fetches the script file" do
        expect(files.count).to eq(1)
        expect(files.first.name).to eq("UsingModule.ps1")
      end
    end

    context "when using module appears only inside a multiline string" do
      let(:repo_contents_json) do
        JSON.dump([{ "name" => "Documented.ps1", "type" => "file" }])
      end

      before do
        stub_content(
          "Documented.ps1",
          <<~POWERSHELL
            $description = "Example:
            using module Pester"
          POWERSHELL
        )
      end

      it "raises DependencyFileNotFound" do
        expect { files }.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "when using and module are joined by a line continuation" do
      let(:repo_contents_json) do
        JSON.dump([{ "name" => "Continued.ps1", "type" => "file" }])
      end

      before do
        stub_content(
          "Continued.ps1",
          <<~POWERSHELL
            using `
            module Pester
          POWERSHELL
        )
      end

      it "fetches the script file" do
        expect(files.first.name).to eq("Continued.ps1")
      end
    end

    context "when using module follows another using statement on the same line" do
      let(:repo_contents_json) do
        JSON.dump([{ "name" => "SameLine.ps1", "type" => "file" }])
      end

      before do
        stub_content(
          "SameLine.ps1",
          "using namespace System; using module Pester\n"
        )
      end

      it "fetches the script file" do
        expect(files.first.name).to eq("SameLine.ps1")
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

    context "when a .ps1 script only has #Requires -Modules inside a block comment" do
      let(:repo_contents_json) do
        JSON.dump([{ "name" => "Documented.ps1", "type" => "file" }])
      end

      before { stub_content("Documented.ps1", fixture("ps1", "commented_out_requires_script.ps1")) }

      it "raises DependencyFileNotFound, since there's no active directive" do
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

    context "when a configured subdirectory contains many mixed files" do
      let(:directory) { "/src/modules" }
      let(:manifest_content) { fixture("psd1", "nested_modules_manifest.psd1") }
      let(:requires_content) { fixture("ps1", "requires_script.ps1") }
      let(:using_content) { fixture("psm1", "using_module.psm1") }
      let(:declaration_free_content) { fixture("ps1", "no_requires_script.ps1") }
      let(:candidate_names) { %w(MyModule.PSD1 Deploy.Ps1 Library.pSm1 NoRequires.ps1) }
      let(:irrelevant_entries) do
        Array.new(995) { |index| { "name" => "notes-#{index}.txt", "type" => "file" } }
      end
      let(:repo_contents_json) do
        JSON.dump(
          irrelevant_entries +
          [
            { "name" => "MyModule.PSD1", "type" => "file" },
            { "name" => "Deploy.Ps1", "type" => "file" },
            { "name" => "Library.pSm1", "type" => "file" },
            { "name" => "NoRequires.ps1", "type" => "file" },
            { "name" => "Nested.psd1", "type" => "dir" }
          ]
        )
      end

      before do
        stub_content("MyModule.PSD1", manifest_content)
        stub_content("Deploy.Ps1", requires_content)
        stub_content("Library.pSm1", using_content)
        stub_content("NoRequires.ps1", declaration_free_content)
      end

      it "lists once, fetches each candidate once, and preserves supported files" do
        expect(files.map { |file| [file.name, file.directory, file.type, file.content] }).to eq(
          [
            ["MyModule.PSD1", directory, "file", manifest_content],
            ["Deploy.Ps1", directory, "file", requires_content],
            ["Library.pSm1", directory, "file", using_content]
          ]
        )

        expect(WebMock).to have_requested(:get, directory_contents_url).once
        candidate_names.each do |name|
          path = "#{directory.delete_prefix('/')}/#{name}"
          expect(WebMock).to have_requested(:get, url + "#{path}?ref=sha").once
        end
        expect(WebMock).not_to have_requested(
          :get,
          url + "#{directory.delete_prefix('/')}/notes-0.txt?ref=sha"
        )
        expect(WebMock).not_to have_requested(
          :get,
          url + "#{directory.delete_prefix('/')}/Nested.psd1?ref=sha"
        )
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
