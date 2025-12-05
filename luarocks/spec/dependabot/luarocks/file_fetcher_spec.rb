# typed: false
# frozen_string_literal: true

require "spec_helper"
require "ostruct"
require "dependabot/source"
require "dependabot/dependency_file"
require "dependabot/luarocks/file_fetcher"

RSpec.describe Dependabot::Luarocks::FileFetcher do
  let(:credentials) { [] }
  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "acme/demo", directory: "/")
  end
  let(:fetcher) do
    described_class.new(source: source, credentials: credentials)
  end

  describe ".required_files_in?" do
    it "returns true when a rockspec is present" do
      expect(described_class.required_files_in?(%w(app.rockspec other.txt))).to be(true)
    end

    it "returns false when neither is present" do
      expect(described_class.required_files_in?(%w(foo.txt bar.lua))).to be(false)
    end
  end

  describe "#fetch_files" do
    before do
      allow(fetcher).to receive_messages(
        allow_beta_ecosystems?: true,
        repo_contents: repo_contents
      )
      allow(fetcher).to receive(:fetch_file_from_host) do |name|
        Dependabot::DependencyFile.new(name: name, content: "content")
      end
    end

    context "when a rockspec exists" do
      let(:repo_contents) { [OpenStruct.new(name: "demo.rockspec", type: "file")] }

      it "returns the rockspec file" do
        expect(fetcher.files.map(&:name)).to eq(["demo.rockspec"])
      end
    end

    context "when required files are missing" do
      let(:repo_contents) { [] }

      it "raises a helpful error" do
        expect { fetcher.files }.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end
end
