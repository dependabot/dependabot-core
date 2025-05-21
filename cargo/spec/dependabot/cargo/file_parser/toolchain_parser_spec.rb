# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/file_parser/toolchain_parser"
require "dependabot/dependency_file"

RSpec.describe Dependabot::Cargo::FileParser::ToolchainParser do
  let(:parser) { described_class.new(toolchain_file) }

  describe "#parse" do
    subject(:dependency) { parser.parse }

    context "with a plaintext toolchain file" do
      let(:toolchain_file) do
        Dependabot::DependencyFile.new(
          name: "rust-toolchain",
          content: toolchain_content
        )
      end

      context "with a specific version" do
        let(:toolchain_content) { "1.72.0" }

        it "returns a dependency with the correct details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("rust-toolchain")
          expect(dependency.version).to eq("1.72.0")
          expect(dependency.requirements).to eq([])
          expect(dependency.package_manager).to eq("cargo")
          expect(dependency.metadata[:toolchain_channel]).to eq({
            channel: nil,
            date: nil,
            version: "1.72.0"
          })
        end
      end

      context "with a channel" do
        let(:toolchain_content) { "nightly" }

        it "returns a dependency with the correct details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("rust-toolchain")
          expect(dependency.version).to eq("nightly")
          expect(dependency.requirements).to eq([])
          expect(dependency.package_manager).to eq("cargo")
          expect(dependency.metadata[:toolchain_channel]).to eq({
            channel: "nightly",
            date: nil,
            version: nil
          })
        end
      end

      context "with a channel and date" do
        let(:toolchain_content) { "nightly-2023-05-15" }

        it "returns a dependency with the correct details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("rust-toolchain")
          expect(dependency.version).to eq("nightly-2023-05-15")
          expect(dependency.requirements).to eq([])
          expect(dependency.package_manager).to eq("cargo")
          expect(dependency.metadata[:toolchain_channel]).to eq({
            channel: "nightly",
            date: "2023-05-15",
            version: nil
          })
        end
      end
    end

    context "with a TOML toolchain file" do
      let(:toolchain_file) do
        Dependabot::DependencyFile.new(
          name: "rust-toolchain.toml",
          content: toolchain_content
        )
      end

      context "with a simple channel specification" do
        let(:toolchain_content) do
          <<~TOML
            [toolchain]
            channel = "1.72.0"
          TOML
        end

        it "returns a dependency with the correct details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("rust-toolchain")
          expect(dependency.version).to eq("1.72.0")
          expect(dependency.requirements).to eq([])
          expect(dependency.package_manager).to eq("cargo")
          expect(dependency.metadata[:toolchain_channel]).to eq({
            channel: nil,
            date: nil,
            version: "1.72.0"
          })
        end
      end

      context "with a nightly channel specification" do
        let(:toolchain_content) do
          <<~TOML
            [toolchain]
            channel = "nightly-2023-05-15"
            components = ["rustfmt", "clippy"]
          TOML
        end

        it "returns a dependency with the correct details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("rust-toolchain")
          expect(dependency.version).to eq("nightly-2023-05-15")
          expect(dependency.requirements).to eq([])
          expect(dependency.package_manager).to eq("cargo")
          expect(dependency.metadata[:toolchain_channel]).to eq({
            channel: "nightly",
            date: "2023-05-15",
            version: nil
          })
        end
      end

      context "with a missing channel in TOML" do
        let(:toolchain_content) do
          <<~TOML
            [toolchain]
            components = ["rustfmt", "clippy"]
          TOML
        end

        it "raises a DependencyFileNotParseable error" do
          expect { dependency }.to raise_error(Dependabot::DependencyFileNotParseable)
        end
      end

      context "with invalid TOML" do
        let(:toolchain_content) do
          <<~TOML
            [toolchain
            channel = "1.72.0"
          TOML
        end

        it "raises a DependencyFileNotParseable error" do
          expect { dependency }.to raise_error(Dependabot::DependencyFileNotParseable)
        end
      end
    end

    context "with an empty file" do
      let(:toolchain_file) do
        Dependabot::DependencyFile.new(
          name: "rust-toolchain",
          content: ""
        )
      end

      it "returns nil" do
        expect(dependency).to be_nil
      end
    end

    context "with a nil content file" do
      let(:toolchain_file) do
        Dependabot::DependencyFile.new(
          name: "rust-toolchain",
          content: nil
        )
      end

      it "returns nil" do
        expect(dependency).to be_nil
      end
    end
  end
end
