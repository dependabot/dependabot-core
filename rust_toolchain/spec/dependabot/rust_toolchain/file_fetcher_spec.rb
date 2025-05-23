# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/rust_toolchain/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::RustToolchain::FileFetcher do
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: [], repo_contents_path: repo_contents_path)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/rust-toolchain-example",
      directory: directory
    )
  end

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    subject(:required_files_in?) { described_class.required_files_in?(filenames) }

    context "when rust-toolchain.toml is present" do
      let(:filenames) { ["rust-toolchain.toml"] }

      it { is_expected.to be(true) }
    end

    context "when rust-toolchain is present" do
      let(:filenames) { ["rust-toolchain"] }

      it { is_expected.to be(true) }
    end

    context "when both files are present" do
      let(:filenames) { ["rust-toolchain.toml", "rust-toolchain"] }

      it { is_expected.to be(true) }
    end

    context "when rust-toolchain.toml is in a subdirectory" do
      let(:filenames) { ["src/rust-toolchain.toml"] }

      it { is_expected.to be(true) }
    end

    context "when rust-toolchain is in a subdirectory" do
      let(:filenames) { ["config/rust-toolchain"] }

      it { is_expected.to be(true) }
    end

    context "when neither file is present" do
      let(:filenames) { ["Cargo.toml", "src/main.rs"] }

      it { is_expected.to be(false) }
    end

    context "when similar but incorrect filenames are present" do
      let(:filenames) { ["rust-toolchain.txt", "toolchain.toml", "rust-tool.toml"] }

      it { is_expected.to be(false) }
    end

    context "when empty filenames array" do
      let(:filenames) { [] }

      it { is_expected.to be(false) }
    end

    context "when mixed with other files" do
      let(:filenames) { ["Cargo.toml", "README.md", "rust-toolchain.toml", "src/lib.rs"] }

      it { is_expected.to be(true) }
    end
  end

  describe ".required_files_message" do
    subject(:required_files_message) { described_class.required_files_message }

    it "returns a helpful message" do
      expect(required_files_message)
        .to eq("Repo must contain a rust-toolchain.toml or rust-toolchain file")
    end
  end

  describe "#fetch_files" do
    subject(:fetch_files) { file_fetcher_instance.files }

    context "with rust-toolchain.toml in repo root" do
      let(:project_name) { "toml_config_only" }
      let(:directory) { "/" }

      it "fetches the rust-toolchain.toml file" do
        expect(fetch_files.map(&:name)).to match_array(%w(rust-toolchain.toml))
      end

      it "returns the correct file content" do
        file = fetch_files.find { |f| f.name == "rust-toolchain.toml" }
        expect(file.content).to include("channel")
      end
    end

    context "with rust-toolchain in repo root" do
      let(:project_name) { "plain_config_only" }
      let(:directory) { "/" }

      it "fetches the rust-toolchain file" do
        expect(fetch_files.map(&:name)).to match_array(%w(rust-toolchain))
      end

      it "returns the correct file content" do
        file = fetch_files.find { |f| f.name == "rust-toolchain" }
        expect(file.content).to be_a(String)
      end
    end

    context "with both rust-toolchain.toml and rust-toolchain files" do
      let(:project_name) { "both_configs" }
      let(:directory) { "/" }

      it "fetches both files" do
        expect(fetch_files.map(&:name)).to match_array(%w(rust-toolchain.toml rust-toolchain))
      end
    end

    context "with rust-toolchain.toml in a subdirectory" do
      let(:project_name) { "toml_config_only" }
      let(:directory) { "/subdir" }

      it "fetches the rust-toolchain.toml file from the subdirectory" do
        expect(fetch_files.map(&:name)).to match_array(%w(rust-toolchain.toml))
      end
    end

    context "without any rust-toolchain files" do
      let(:project_name) { "no_config" }
      let(:directory) { "/" }

      it "raises a helpful error" do
        expect { fetch_files }
          .to raise_error(Dependabot::DependencyFileNotFound)
          .with_message("Repo must contain a rust-toolchain.toml or rust-toolchain file")
      end
    end

    context "when directory doesn't exist" do
      let(:project_name) { "toml_config_only" }
      let(:directory) { "/nonexistent" }

      it "raises a helpful error" do
        expect { fetch_files }
          .to raise_error(Dependabot::DependencyFileNotFound)
          .with_message("Repo must contain a rust-toolchain.toml or rust-toolchain file")
      end
    end
  end
end
