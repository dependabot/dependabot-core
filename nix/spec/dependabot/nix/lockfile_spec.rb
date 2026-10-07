# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/lockfile"

RSpec.describe Dependabot::Nix::Lockfile do
  describe "root input resolution" do
    subject(:lockfile) { described_class.new(content) }

    let(:content) do
      File.read(File.join(__dir__, "fixtures", "flake.lock"))
    end

    it "returns the lockfile version and root input names" do
      expect(lockfile.version).to eq(7)
      expect(lockfile.root_input_names).to contain_exactly("flake-utils", "nixpkgs")
    end

    it "resolves a direct input path and node" do
      expect(lockfile.input_path("nixpkgs")).to eq(["nixpkgs"])
      expect(lockfile.locked_revision("nixpkgs"))
        .to eq("3030f185ba6a4bf4f18b87f345f104e6a6961f34")
      expect(lockfile.original_source("nixpkgs"))
        .to include("type" => "github", "ref" => "nixos-unstable")
      expect(lockfile.locked_source("nixpkgs"))
        .to include(
          "type" => "github",
          "rev" => "3030f185ba6a4bf4f18b87f345f104e6a6961f34"
        )
    end

    context "when a root input follows a nested input path" do
      let(:content) do
        <<~JSON
          {
            "nodes": {
              "parent-node": {
                "inputs": {
                  "nested": "target-node"
                },
                "locked": {
                  "rev": "parent-revision"
                },
                "original": {
                  "type": "github",
                  "owner": "example",
                  "repo": "parent"
                }
              },
              "target-node": {
                "locked": {
                  "rev": "target-revision"
                },
                "original": {
                  "type": "gitlab",
                  "owner": "example",
                  "repo": "target",
                  "ref": "main"
                }
              },
              "root": {
                "inputs": {
                  "alias": ["parent", "nested"],
                  "parent": "parent-node"
                }
              }
            },
            "root": "root",
            "version": 7
          }
        JSON
      end

      it "returns the followed path and target node" do
        expect(lockfile.input_path("alias")).to eq(%w(parent nested))
        expect(lockfile.locked_revision("alias")).to eq("target-revision")
        expect(lockfile.original_source("alias"))
          .to include("type" => "gitlab", "ref" => "main")
      end
    end

    context "when a follows path is cyclic" do
      let(:content) do
        <<~JSON
          {
            "nodes": {
              "root": {
                "inputs": {
                  "first": ["second"],
                  "second": ["first"]
                }
              }
            },
            "root": "root",
            "version": 7
          }
        JSON
      end

      it "returns nil for the cycle" do
        expect(lockfile.input_node("first")).to be_nil
        expect(lockfile.locked_revision("first")).to be_nil
      end
    end
  end
end
