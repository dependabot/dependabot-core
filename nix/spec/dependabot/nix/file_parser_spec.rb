# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/nix/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Nix::FileParser do
  subject(:parser) do
    described_class.new(
      dependency_files: dependency_files,
      source: source
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/nix-project",
      directory: "/"
    )
  end

  let(:dependency_files) { [flake_nix, flake_lock] }

  let(:flake_nix) do
    Dependabot::DependencyFile.new(
      name: "flake.nix",
      content: flake_nix_content
    )
  end

  let(:flake_lock) do
    Dependabot::DependencyFile.new(
      name: "flake.lock",
      content: flake_lock_content
    )
  end

  let(:flake_nix_content) { fixture("flake.nix") }
  let(:flake_lock_content) { fixture("flake.lock") }

  def fixture(filename)
    File.read(File.join(__dir__, "fixtures", filename))
  end

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    context "with a standard flake.lock" do
      it "returns the correct number of dependencies" do
        expect(dependencies.length).to eq(2)
      end

      it "parses nixpkgs correctly" do
        nixpkgs = dependencies.find { |d| d.name == "nixpkgs" }
        expect(nixpkgs).to be_a(Dependabot::Dependency)
        expect(nixpkgs.version).to eq("3030f185ba6a4bf4f18b87f345f104e6a6961f34")
        expect(nixpkgs.package_manager).to eq("nix")
        expect(nixpkgs.requirements).to eq(
          [{
            requirement: nil,
            file: "flake.lock",
            source: {
              type: "git",
              url: "https://github.com/NixOS/nixpkgs",
              branch: "nixos-unstable",
              ref: "nixos-unstable"
            },
            groups: []
          }]
        )
      end

      it "parses flake-utils correctly" do
        flake_utils = dependencies.find { |d| d.name == "flake-utils" }
        expect(flake_utils).to be_a(Dependabot::Dependency)
        expect(flake_utils.version).to eq("b1d9ab70662946ef0850d488da1c9019f3a9752a")
        expect(flake_utils.requirements).to eq(
          [{
            requirement: nil,
            file: "flake.lock",
            source: {
              type: "git",
              url: "https://github.com/numtide/flake-utils",
              branch: nil,
              ref: nil
            },
            groups: []
          }]
        )
      end
    end

    context "with a single-input flake.lock" do
      let(:flake_lock_content) { fixture("flake_single_input.lock") }

      it "returns one dependency" do
        expect(dependencies.length).to eq(1)
        expect(dependencies.first.name).to eq("nixpkgs")
      end
    end

    context "with path inputs that should be skipped" do
      let(:flake_lock_content) { fixture("flake_with_path_input.lock") }

      it "skips path-type inputs" do
        expect(dependencies.length).to eq(1)
        expect(dependencies.first.name).to eq("nixpkgs")
      end
    end

    context "with gitlab inputs" do
      let(:flake_lock_content) { fixture("flake_with_gitlab.lock") }

      it "builds gitlab URLs correctly" do
        gitlab_dep = dependencies.find { |d| d.name == "my-gitlab-dep" }
        expect(gitlab_dep.requirements.first[:source][:url])
          .to eq("https://gitlab.com/myorg/myrepo")
      end
    end

    context "with follows inputs" do
      let(:flake_lock_content) { fixture("flake_with_follows.lock") }

      it "resolves all three root inputs" do
        expect(dependencies.length).to eq(3)
        expect(dependencies.map(&:name)).to contain_exactly("nixpkgs", "flake-utils", "my-overlay")
      end

      it "resolves the overlay dependency correctly" do
        overlay = dependencies.find { |d| d.name == "my-overlay" }
        expect(overlay.version).to eq("aaaa1111bbbb2222cccc3333dddd4444eeee5555")
        expect(overlay.requirements.first[:source][:url])
          .to eq("https://github.com/example/my-overlay")
      end
    end

    context "with a custom host (self-hosted GitHub Enterprise)" do
      let(:flake_lock_content) { fixture("flake_with_custom_host.lock") }

      it "uses the host field in the URL" do
        dep = dependencies.find { |d| d.name == "internal-lib" }
        expect(dep.requirements.first[:source][:url])
          .to eq("https://github.corp.example.com/myteam/internal-lib")
      end
    end
  end
end
