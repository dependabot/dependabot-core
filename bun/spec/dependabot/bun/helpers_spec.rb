# typed: false
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "dependabot/bun/helpers"

RSpec.describe Dependabot::Bun::Helpers do
  describe ".with_lockfile_changes_allowed" do
    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { example.run }
      end
    end

    def write_bunfig(content)
      File.write("bunfig.toml", content)
    end

    def bunfig
      File.read("bunfig.toml")
    end

    def bunfig_seen_by_block
      seen = nil
      described_class.with_lockfile_changes_allowed { seen = File.exist?("bunfig.toml") ? bunfig : nil }
      seen
    end

    context "without a bunfig.toml" do
      it "runs the block without creating one" do
        expect(described_class.with_lockfile_changes_allowed { :done }).to eq(:done)
        expect(File.exist?("bunfig.toml")).to be(false)
      end
    end

    context "when the [install] table freezes the lockfile" do
      before { write_bunfig("[install]\nfrozenLockfile = true\n") }

      it "turns the freeze off" do
        expect(bunfig_seen_by_block).to eq("[install]\nfrozenLockfile = false\n")
      end
    end

    context "when the block finishes" do
      before { write_bunfig("[install]\nfrozenLockfile = true\n") }

      it "returns the block's value and puts the bunfig.toml back as it was" do
        expect(described_class.with_lockfile_changes_allowed { :done }).to eq(:done)
        expect(bunfig).to eq("[install]\nfrozenLockfile = true\n")
      end
    end

    context "when the block raises" do
      before { write_bunfig("[install]\nfrozenLockfile = true\n") }

      it "puts the bunfig.toml back as it was" do
        expect { described_class.with_lockfile_changes_allowed { raise "bun failed" } }
          .to raise_error("bun failed")
        expect(bunfig).to eq("[install]\nfrozenLockfile = true\n")
      end
    end

    context "when the freeze is written with extra whitespace and a trailing comment" do
      before { write_bunfig("[ install ]\n  frozenLockfile   =   true   # CI parity\n") }

      it "turns the freeze off and keeps the comment" do
        expect(bunfig_seen_by_block).to eq("[ install ]\n  frozenLockfile   =   false   # CI parity\n")
      end
    end

    context "when the freeze is a dotted key at the top level" do
      before { write_bunfig("install.frozenLockfile = true\n\n[test]\nroot = \".\"\n") }

      it "turns the freeze off" do
        expect(bunfig_seen_by_block).to eq("install.frozenLockfile = false\n\n[test]\nroot = \".\"\n")
      end
    end

    context "when the file has other settings, tables and comments" do
      let(:original) do
        <<~TOML
          # Settings for this repository
          [install]
          exact = true
          frozenLockfile = true
          minimumReleaseAge = 604800

          [install.scopes]
          "@acme" = { url = "https://npm.acme.test/", token = "$ACME_TOKEN" }

          [test]
          root = "src"
        TOML
      end

      before { write_bunfig(original) }

      it "changes only the freeze" do
        expect(bunfig_seen_by_block).to eq(original.sub("frozenLockfile = true", "frozenLockfile = false"))
      end
    end

    context "when the freeze is already off" do
      before { write_bunfig("[install]\nfrozenLockfile = false\n") }

      it "leaves the file as it is" do
        expect(bunfig_seen_by_block).to eq("[install]\nfrozenLockfile = false\n")
      end
    end

    context "when the freeze is commented out" do
      before { write_bunfig("[install]\n# frozenLockfile = true\n") }

      it "leaves the file as it is" do
        expect(bunfig_seen_by_block).to eq("[install]\n# frozenLockfile = true\n")
      end
    end

    context "when a key with the same name belongs to another table" do
      before { write_bunfig("[install]\nexact = true\n\n[run]\nfrozenLockfile = true\n") }

      it "leaves the file as it is" do
        expect(bunfig_seen_by_block).to eq("[install]\nexact = true\n\n[run]\nfrozenLockfile = true\n")
      end
    end
  end
end
