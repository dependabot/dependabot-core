# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/flake_nix_parser"

RSpec.describe Dependabot::Nix::FlakeNixParser do
  def fixture(name)
    File.read(
      File.join(__dir__, "fixtures", name)
    )
  end

  describe ".find_input_url" do
    context "with dot-notation inputs" do
      let(:content) { fixture("flake.nix") }

      it "finds a URL with a ref" do
        result = described_class.find_input_url(content, "nixpkgs")

        expect(result).not_to be_nil
        expect(result.scheme).to eq("github")
        expect(result.owner).to eq("NixOS")
        expect(result.repo).to eq("nixpkgs")
        expect(result.ref).to eq("nixos-unstable")
        expect(result.full_url).to eq("github:NixOS/nixpkgs/nixos-unstable")
      end

      it "finds a URL without a ref" do
        result = described_class.find_input_url(content, "flake-utils")

        expect(result).not_to be_nil
        expect(result.scheme).to eq("github")
        expect(result.owner).to eq("numtide")
        expect(result.repo).to eq("flake-utils")
        expect(result.ref).to be_nil
      end

      it "returns nil for unknown input names" do
        result = described_class.find_input_url(content, "nonexistent")
        expect(result).to be_nil
      end
    end

    context "with tag-pinned inputs" do
      let(:content) { fixture("flake_with_tag.nix") }

      it "finds the tag ref" do
        result = described_class.find_input_url(content, "devenv")

        expect(result).not_to be_nil
        expect(result.scheme).to eq("github")
        expect(result.owner).to eq("cachix")
        expect(result.repo).to eq("devenv")
        expect(result.ref).to eq("v0.5")
      end
    end

    context "with attribute set syntax" do
      let(:content) { fixture("flake_with_versioned_branch.nix") }

      it "finds URL inside attribute set block" do
        result = described_class.find_input_url(content, "home-manager")

        expect(result).not_to be_nil
        expect(result.scheme).to eq("github")
        expect(result.owner).to eq("nix-community")
        expect(result.repo).to eq("home-manager")
        expect(result.ref).to eq("release-24.11")
      end

      it "still finds dot-notation inputs" do
        result = described_class.find_input_url(content, "nixpkgs")

        expect(result).not_to be_nil
        expect(result.ref).to eq("nixos-24.11")
      end
    end

    context "with gitlab URL" do
      let(:content) do
        <<~NIX
          {
            inputs.mylib.url = "gitlab:myorg/myrepo/main";
            outputs = { self, mylib }: { };
          }
        NIX
      end

      it "parses gitlab scheme" do
        result = described_class.find_input_url(content, "mylib")

        expect(result).not_to be_nil
        expect(result.scheme).to eq("gitlab")
        expect(result.owner).to eq("myorg")
        expect(result.repo).to eq("myrepo")
        expect(result.ref).to eq("main")
      end
    end

    context "with sourcehut URL" do
      let(:content) do
        <<~NIX
          {
            inputs.mylib.url = "sourcehut:~user/myrepo/v1.0";
            outputs = { self, mylib }: { };
          }
        NIX
      end

      it "parses sourcehut scheme with tilde prefix" do
        result = described_class.find_input_url(content, "mylib")

        expect(result).not_to be_nil
        expect(result.scheme).to eq("sourcehut")
        expect(result.owner).to eq("~user")
        expect(result.repo).to eq("myrepo")
        expect(result.ref).to eq("v1.0")
      end
    end

    context "with query parameters" do
      let(:content) do
        <<~NIX
          {
            inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable?host=github.corp.example.com";
            outputs = { self, nixpkgs }: { };
          }
        NIX
      end

      it "captures query params separately" do
        result = described_class.find_input_url(content, "nixpkgs")

        expect(result).not_to be_nil
        expect(result.ref).to eq("nixos-unstable")
        expect(result.query).to eq("host=github.corp.example.com")
      end
    end

    context "with non-shorthand URL" do
      let(:content) do
        <<~NIX
          {
            inputs.mylib.url = "git+https://example.com/repo.git?ref=main";
            outputs = { self, mylib }: { };
          }
        NIX
      end

      it "returns nil for non-shorthand URLs" do
        result = described_class.find_input_url(content, "mylib")
        expect(result).to be_nil
      end
    end

    context "with similar input names" do
      let(:content) do
        <<~NIX
          {
            inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
            inputs.my-nixpkgs.url = "github:myorg/my-nixpkgs/main";
            outputs = { ... }: { };
          }
        NIX
      end

      it "does not match a longer name containing the input name" do
        result = described_class.find_input_url(content, "nixpkgs")

        expect(result).not_to be_nil
        expect(result.owner).to eq("NixOS")
        expect(result.repo).to eq("nixpkgs")
      end
    end

    context "with commented-out input" do
      let(:content) do
        <<~NIX
          {
            # inputs.nixpkgs.url = "github:NixOS/nixpkgs/old-ref";
            inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
            outputs = { ... }: { };
          }
        NIX
      end

      it "skips the commented line and finds the real input" do
        result = described_class.find_input_url(content, "nixpkgs")

        expect(result).not_to be_nil
        expect(result.ref).to eq("nixos-unstable")
      end
    end

    context "with block-commented input" do
      let(:content) do
        <<~NIX
          {
            /* inputs.nixpkgs.url = "github:NixOS/nixpkgs/old-ref"; */
            inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
            outputs = { ... }: { };
          }
        NIX
      end

      it "skips the block comment and finds the real input" do
        result = described_class.find_input_url(content, "nixpkgs")

        expect(result).not_to be_nil
        expect(result.ref).to eq("nixos-unstable")
      end
    end
  end

  describe ".update_input_ref" do
    context "with dot-notation input" do
      let(:content) { fixture("flake_with_tag.nix") }

      it "rewrites the ref in the URL" do
        updated = described_class.update_input_ref(content, "devenv", "v0.6.2")

        expect(updated).to include('"github:cachix/devenv/v0.6.2"')
        expect(updated).not_to include('"github:cachix/devenv/v0.5"')
      end

      it "does not modify other inputs" do
        updated = described_class.update_input_ref(content, "devenv", "v0.6.2")

        expect(updated).to include('"github:NixOS/nixpkgs/nixos-unstable"')
        expect(updated).to include('"github:numtide/flake-utils"')
      end
    end

    context "with attribute set syntax" do
      let(:content) { fixture("flake_with_versioned_branch.nix") }

      it "rewrites the ref inside the attribute set" do
        updated = described_class.update_input_ref(content, "home-manager", "release-25.05")

        expect(updated).to include('"github:nix-community/home-manager/release-25.05"')
        expect(updated).not_to include("release-24.11")
      end

      it "does not modify other inputs" do
        updated = described_class.update_input_ref(content, "home-manager", "release-25.05")

        expect(updated).to include('"github:NixOS/nixpkgs/nixos-24.11"')
      end
    end

    context "with query parameters" do
      let(:content) do
        <<~NIX
          {
            inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11?host=github.corp.example.com";
            outputs = { self, nixpkgs }: { };
          }
        NIX
      end

      it "preserves query parameters" do
        updated = described_class.update_input_ref(content, "nixpkgs", "nixos-25.05")

        expect(updated).to include('"github:NixOS/nixpkgs/nixos-25.05?host=github.corp.example.com"')
      end
    end

    context "when input has no ref" do
      let(:content) { fixture("flake.nix") }

      it "returns nil when there is no ref to update" do
        updated = described_class.update_input_ref(content, "flake-utils", "v2.0")
        expect(updated).to be_nil
      end
    end

    context "when input is not found" do
      let(:content) { fixture("flake.nix") }

      it "returns nil" do
        updated = described_class.update_input_ref(content, "nonexistent", "v1.0")
        expect(updated).to be_nil
      end
    end
  end
end
