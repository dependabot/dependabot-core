# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/rust_toolchain/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::RustToolchain::FileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: []
    )
  end

  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "rust",
      version: "1.70.0",
      previous_version: "1.69.0",
      requirements: [],
      previous_requirements: [],
      package_manager: "rust_toolchain"
    )
  end

  describe ".updated_files_regex" do
    subject(:updated_files_regex) { described_class.updated_files_regex }

    it "returns an array of regexes for rust toolchain files" do
      expect(updated_files_regex).to be_an(Array)
      expect(updated_files_regex).to all(be_a(Regexp))
    end

    it "matches rust-toolchain file" do
      expect(updated_files_regex.any? { |regex| "rust-toolchain" =~ regex }).to be true
    end

    it "matches rust-toolchain.toml file" do
      expect(updated_files_regex.any? { |regex| "rust-toolchain.toml" =~ regex }).to be true
    end

    it "does not match other files" do
      expect(updated_files_regex.any? { |regex| "Cargo.toml" =~ regex }).to be false
      expect(updated_files_regex.any? { |regex| "some-other-file" =~ regex }).to be false
    end
  end

  describe "#updated_dependency_files" do
    context "with rust-toolchain file" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "rust-toolchain",
            content: "1.69.0"
          )
        ]
      end

      before do
        allow(updater).to receive(:file_changed?).and_return(true)
      end

      it "returns updated dependency files" do
        updated_files = updater.updated_dependency_files

        expect(updated_files).to be_an(Array)
        expect(updated_files.length).to eq(1)
        expect(updated_files.first).to be_a(Dependabot::DependencyFile)
        expect(updated_files.first.content).to eq("1.70.0")
      end
    end

    context "with rust-toolchain.toml file" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "rust-toolchain.toml",
            content: "[toolchain]\nchannel = \"1.69.0\""
          )
        ]
      end

      before do
        allow(updater).to receive(:file_changed?).and_return(true)
      end

      it "updates the version in toml content" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to eq("[toolchain]\nchannel = \"1.70.0\"")
      end
    end

    context "with multiple rust toolchain files" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "rust-toolchain",
            content: "1.69.0"
          ),
          Dependabot::DependencyFile.new(
            name: "rust-toolchain.toml",
            content: "[toolchain]\nchannel = \"1.69.0\""
          )
        ]
      end

      before do
        allow(updater).to receive(:file_changed?).and_return(true)
      end

      it "updates both files" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.length).to eq(2)
        expect(updated_files.map(&:name)).to contain_exactly("rust-toolchain", "rust-toolchain.toml")
        expect(updated_files.map(&:content)).to all(include("1.70.0"))
      end
    end

    context "when file has not changed" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "rust-toolchain",
            content: "1.69.0"
          )
        ]
      end

      before do
        allow(updater).to receive(:file_changed?).and_return(false)
      end

      it "returns empty array" do
        updated_files = updater.updated_dependency_files
        expect(updated_files).to be_empty
      end
    end

    context "when file content is nil" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "rust-toolchain",
            content: nil
          )
        ]
      end

      before do
        allow(updater).to receive(:file_changed?).and_return(true)
      end

      it "raises an error" do
        expect { updater.updated_dependency_files }.to raise_error(TypeError)
      end
    end
  end

  describe "#check_required_files" do
    context "when dependency files are present" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "rust-toolchain",
            content: "1.69.0"
          )
        ]
      end

      it "does not raise an error" do
        expect { updater.send(:check_required_files) }.not_to raise_error
      end
    end

    context "when no dependency files are present" do
      let(:dependency_files) { [] }

      it "raises an error" do
        expect { updater.send(:check_required_files) }.to raise_error("No global.json configuration!")
      end
    end
  end

  describe "#dependency" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "rust-toolchain",
          content: "1.69.0"
        )
      ]
    end

    it "returns the first dependency" do
      expect(updater.send(:dependency)).to eq(dependency)
    end

    context "when dependencies is empty" do
      let(:dependencies) { [] }

      it "raises an error" do
        expect { updater.send(:dependency) }.to raise_error(TypeError)
      end
    end
  end

  describe "#rust_toolchain_files" do
    context "with mixed file types" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(name: "rust-toolchain", content: "1.69.0"),
          Dependabot::DependencyFile.new(name: "rust-toolchain.toml", content: "[toolchain]\nchannel = \"1.69.0\""),
          Dependabot::DependencyFile.new(name: "Cargo.toml", content: "[package]\nname = \"test\""),
          Dependabot::DependencyFile.new(name: "other-file", content: "content")
        ]
      end

      it "returns only rust toolchain files" do
        files = updater.send(:rust_toolchain_files)

        expect(files.length).to eq(2)
        expect(files.map(&:name)).to contain_exactly("rust-toolchain", "rust-toolchain.toml")
      end
    end

    context "with no rust toolchain files" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(name: "Cargo.toml", content: "[package]\nname = \"test\"")
        ]
      end

      it "returns empty array" do
        files = updater.send(:rust_toolchain_files)
        expect(files).to be_empty
      end
    end

    context "when RUST_TOOLCHAIN_FILENAME and RUST_TOOLCHAIN_TOML_FILENAME constants are not defined" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(name: "rust-toolchain", content: "1.69.0")
        ]
      end

      before do
        # Stub the constants if they don't exist in the class
        unless described_class.const_defined?(:RUST_TOOLCHAIN_FILENAME)
          stub_const("#{described_class}::RUST_TOOLCHAIN_FILENAME", "rust-toolchain")
        end
        unless described_class.const_defined?(:RUST_TOOLCHAIN_TOML_FILENAME)
          stub_const("#{described_class}::RUST_TOOLCHAIN_TOML_FILENAME", "rust-toolchain.toml")
        end
      end

      it "uses the constants to filter files" do
        files = updater.send(:rust_toolchain_files)
        expect(files.length).to eq(1)
        expect(files.first.name).to eq("rust-toolchain")
      end
    end
  end

  describe "#update" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "rust-toolchain",
          content: "1.69.0"
        )
      ]
    end

    it "replaces previous version with new version" do
      content = "1.69.0"
      result = updater.send(:update, content)

      expect(result).to eq("1.70.0")
    end

    it "replaces multiple occurrences" do
      content = "version: 1.69.0\nother: 1.69.0"
      result = updater.send(:update, content)

      expect(result).to eq("version: 1.70.0\nother: 1.70.0")
    end

    it "handles complex content with version embedded" do
      content = <<~TOML
        [toolchain]
        channel = "1.69.0"
        components = ["rustfmt", "clippy"]
        targets = ["x86_64-unknown-linux-gnu"]
      TOML

      result = updater.send(:update, content)

      expected = <<~TOML
        [toolchain]
        channel = "1.70.0"
        components = ["rustfmt", "clippy"]
        targets = ["x86_64-unknown-linux-gnu"]
      TOML

      expect(result).to eq(expected)
    end

    context "when dependency has nil versions" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "rust",
          version: nil,
          previous_version: "1.69.0",
          requirements: [],
          previous_requirements: [],
          package_manager: "rust_toolchain"
        )
      end

      it "raises an error" do
        expect { updater.send(:update, "1.69.0") }.to raise_error(TypeError)
      end
    end

    context "when previous version is nil" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "rust",
          version: "1.70.0",
          previous_version: nil,
          requirements: [],
          previous_requirements: [],
          package_manager: "rust_toolchain"
        )
      end

      it "raises an error" do
        expect { updater.send(:update, "1.69.0") }.to raise_error(TypeError)
      end
    end
  end

  it_behaves_like "a dependency file updater"
end
