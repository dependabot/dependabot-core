# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/lockfile"

RSpec.describe Dependabot::Nix::Lockfile do
  extend T::Sig

  sig { returns(Dependabot::Nix::Lockfile) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:lockfile) { described_class.from_file(file) }

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::DependencyFile) }
  let(:file) do
    Dependabot::DependencyFile.new(
      name: "flake.lock",
      directory: "/nested",
      content: {
        "version" => 7,
        "root" => "root",
        "nodes" => {
          "root" => {
            "inputs" => { "base" => "package", "follow" => ["base"], "empty" => [], "bad" => ["base", false] }
          },
          "package" => { "locked" => locked, "original" => original }
        }
      }.to_json
    )
  end

  sig { returns(T::Hash[String, Object]) }
  let(:locked) { { "type" => "github", "owner" => "NixOS", "repo" => "nixpkgs", "rev" => "revision" } }

  sig { returns(T::Hash[String, Object]) }
  let(:original) { { "type" => "github", "ref" => "main" } }
  # rubocop:enable RSpec/ScatteredLet

  it "retains parsed source fields after resolving a follows path" do
    expect(lockfile.dependency_input("follow")).to have_attributes(
      type: "git", revision: "revision", url: "https://github.com/NixOS/nixpkgs", ref: "main"
    )
    expect(lockfile.input_path("follow")).to eq(["base"])
    expect(lockfile.input_path("empty")).to be_nil
    expect(lockfile.input_path("bad")).to be_nil
  end

  context "with a malformed required source field" do
    sig { returns(T::Hash[String, Object]) }
    let(:locked) { super().merge("owner" => false) }

    it "reports the input, field and dependency file" do
      expect { lockfile.dependency_input("base") }
        .to raise_error(Dependabot::DependencyFileNotParseable, /base.*owner/) do |error|
        expect(error.file_path).to eq(file.path)
      end
    end

    context "when the original input is revision-pinned" do
      sig { returns(T::Hash[String, Object]) }
      let(:original) { super().merge("rev" => "pinned") }

      it "skips before decoding unconsumed source fields" do
        expect(lockfile.dependency_input("base")).to be_nil
      end
    end
  end

  context "with an indirect channel resolved to a release tarball" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(T::Hash[String, Object]) }
    let(:locked) do
      {
        "type" => "tarball",
        "rev" => "revision",
        "url" => "https://releases.nixos.org/nixos/26.05/nixos-26.05.123/nixexprs.tar.xz"
      }
    end

    sig { returns(T::Hash[String, Object]) }
    let(:original) { { "type" => "indirect", "id" => "nixpkgs", "ref" => "nixos-unstable" } }
    # rubocop:enable RSpec/ScatteredLet

    it "retains the canonical channel and release revision" do
      expect(lockfile.dependency_input("base")).to have_attributes(
        type: "tarball",
        revision: "revision",
        ref: "nixos-unstable",
        url: "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz"
      )
    end
  end
end
