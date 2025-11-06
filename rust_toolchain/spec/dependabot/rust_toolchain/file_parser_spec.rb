# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/rust_toolchain/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::RustToolchain::FileParser do
  let(:dependency_files) { [dependency_file] }
  let(:parser) { described_class.new(dependency_files: dependency_files, source: nil) }

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    context "with a TOML rust-toolchain file" do
      let(:dependency_file) do
        Dependabot::DependencyFile.new(
          name: "rust-toolchain.toml",
          content: toml_content
        )
      end

      context "with a valid channel" do
        let(:toml_content) do
          <<~TOML
            [toolchain]
            channel = "stable"
          TOML
        end

        it "parses the dependency correctly" do
          dependencies = parser.parse
          expect(dependencies.count).to eq(1)

          dependency = dependencies.first
          expect(dependency.name).to eq("rust-toolchain")
          expect(dependency.version).to eq("stable")
          expect(dependency.requirements).to eq(
            [
              {
                file: "rust-toolchain.toml",
                requirement: "stable",
                groups: [],
                source: nil
              }
            ]
          )
        end
      end

      context "with a nightly channel" do
        let(:toml_content) do
          <<~TOML
            [toolchain]
            channel = "nightly-2023-01-01"
          TOML
        end

        it "parses the nightly channel" do
          dependencies = parser.parse
          expect(dependencies.count).to eq(1)

          dependency = dependencies.first
          expect(dependency.version).to eq("nightly-2023-01-01")
        end
      end

      context "with missing toolchain section" do
        let(:toml_content) do
          <<~TOML
            [some_other_section]
            key = "value"
          TOML
        end

        it "raises a parsing error" do
          expect { parser.parse }.to raise_error(Dependabot::DependencyFileNotParseable)
        end
      end

      context "with invalid TOML" do
        let(:toml_content) { "invalid toml content [" }

        it "raises a parsing error" do
          expect { parser.parse }.to raise_error(Dependabot::DependencyFileNotParseable)
        end
      end

      context "with empty channel" do
        let(:toml_content) do
          <<~TOML
            [toolchain]
            channel = ""
          TOML
        end

        it "returns no dependencies" do
          dependencies = parser.parse
          expect(dependencies).to be_empty
        end
      end
    end

    context "with a plaintext rust-toolchain file" do
      let(:dependency_file) do
        Dependabot::DependencyFile.new(
          name: "rust-toolchain",
          content: plaintext_content
        )
      end

      context "with a stable channel" do
        let(:plaintext_content) { "stable" }

        it "parses the dependency correctly" do
          dependencies = parser.parse
          expect(dependencies.count).to eq(1)

          dependency = dependencies.first
          expect(dependency.name).to eq("rust-toolchain")
          expect(dependency.version).to eq("stable")
        end
      end

      context "with whitespace around content" do
        let(:plaintext_content) { "  nightly  \n" }

        it "strips whitespace and parses correctly" do
          dependencies = parser.parse
          expect(dependencies.count).to eq(1)

          dependency = dependencies.first
          expect(dependency.version).to eq("nightly")
        end
      end

      context "with empty content" do
        let(:plaintext_content) { "" }

        it "returns no dependencies" do
          dependencies = parser.parse
          expect(dependencies).to be_empty
        end
      end

      context "with only whitespace" do
        let(:plaintext_content) { "   \n  " }

        it "returns no dependencies" do
          dependencies = parser.parse
          expect(dependencies).to be_empty
        end
      end
    end

    context "with no dependency files" do
      let(:dependency_files) { [] }

      it "raises an error" do
        expect { parser.parse }.to raise_error(/Could not find any dependency files to parse/)
      end
    end
  end

  describe "#check_required_files" do
    context "with dependency files present" do
      let(:dependency_file) do
        Dependabot::DependencyFile.new(
          name: "rust-toolchain",
          content: "stable"
        )
      end

      it "does not raise an error" do
        expect { parser.send(:check_required_files) }.not_to raise_error
      end
    end

    context "with no dependency files" do
      let(:dependency_files) { [] }

      it "raises an error" do
        expect { parser.send(:check_required_files) }.to raise_error(/Could not find any dependency files to parse/)
      end
    end
  end
end
