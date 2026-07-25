# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/vcpkg/package/versions_database"

RSpec.describe Dependabot::Vcpkg::Package::VersionsDatabase do
  subject(:database) { described_class.new(repository_path: repository_path) }

  let(:repository_path) { "/opt/vcpkg" }
  let(:zlib_versions) do
    {
      "versions" => [
        { "git-tree" => "a" * 40, "version" => "1.3.1", "port-version" => 0 },
        { "git-tree" => "b" * 40, "version" => "1.3", "port-version" => 1 },
        { "git-tree" => "c" * 40, "version-string" => "1.2.11", "port-version" => 0 },
        { "git-tree" => "d" * 40, "version-date" => "2020-01-01" },
        { "git-tree" => "e" * 40 }
      ]
    }.to_json
  end
  let(:baseline) do
    {
      "default" => {
        "zlib" => { "baseline" => "1.3.1", "port-version" => 0 },
        "fmt" => { "baseline" => "7.1.3", "port-version" => 1 },
        "broken" => { "port-version" => 1 }
      }
    }.to_json
  end

  before do
    allow(File).to receive(:directory?).with("/opt/vcpkg/.git").and_return(true)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, **|
      case command
      when "git fetch --quiet --tags --force origin" then ""
      when "git rev-parse --verify --quiet origin/master" then "#{'f' * 40}\n"
      when "git show origin/master:versions/z-/zlib.json" then zlib_versions
      when "git show origin/master:versions/b-/broken.json" then "{ not json"
      when "git show origin/master:versions/baseline.json", "git show 2025.06.13:versions/baseline.json"
        baseline
      when "git tag --list" then "2025.06.13\n2021.04.30\nv2024.12.16\nnot-a-release\n"
      when "git rev-list -n 1 2025.06.13" then "#{'1' * 40}\n"
      else
        raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "no such path", error_context: { command: command }
        )
      end
    end
  end

  describe "#available?" do
    it { expect(database.available?).to be(true) }

    context "when the checkout is missing" do
      before { allow(File).to receive(:directory?).with("/opt/vcpkg/.git").and_return(false) }

      it { expect(database.available?).to be(false) }

      it "runs no git commands" do
        database.versions_for("zlib")

        expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
      end
    end
  end

  describe "#registry_ref" do
    it "prefers the fetched remote branch" do
      expect(database.registry_ref).to eq("origin/master")
    end

    it "fetches the registry so newly published versions are visible" do
      database.registry_ref

      expect(Dependabot::SharedHelpers)
        .to have_received(:run_shell_command)
        .with("git fetch --quiet --tags --force origin", cwd: "/opt/vcpkg")
    end

    it "fetches at most once" do
      3.times { database.versions_for("zlib") }

      expect(Dependabot::SharedHelpers)
        .to have_received(:run_shell_command)
        .with("git fetch --quiet --tags --force origin", cwd: "/opt/vcpkg")
        .once
    end
  end

  describe "#versions_for" do
    subject(:versions) { database.versions_for("zlib") }

    it "returns every published version, newest first" do
      expect(versions.map { |entry| entry.version.to_s }).to eq(["1.3.1", "1.3#1", "1.2.11", "2020-01-01"])
    end

    it "records the scheme each version was published under" do
      expect(versions.map(&:scheme)).to eq(%w(version version version-string version-date))
    end

    it "records the git tree so release dates can be looked up" do
      expect(versions.first.git_tree).to eq("a" * 40)
    end

    it "skips entries with no version" do
      expect(versions.map(&:git_tree)).not_to include("e" * 40)
    end

    it "memoises the lookup" do
      2.times { database.versions_for("zlib") }

      expect(Dependabot::SharedHelpers)
        .to have_received(:run_shell_command)
        .with("git show origin/master:versions/z-/zlib.json", cwd: "/opt/vcpkg")
        .once
    end

    context "with an unknown port" do
      it "returns nothing" do
        expect(database.versions_for("definitely-not-a-port")).to eq([])
      end
    end

    context "with an unparseable versions file" do
      it "returns nothing" do
        expect(database.versions_for("broken")).to eq([])
      end
    end
  end

  describe "#baseline_version_for" do
    it "returns the version floor the ref sets" do
      expect(database.baseline_version_for(port: "zlib", ref: "2025.06.13").to_s).to eq("1.3.1")
    end

    it "includes the port version" do
      expect(database.baseline_version_for(port: "fmt", ref: "2025.06.13").to_s).to eq("7.1.3#1")
    end

    it "returns nil for a port the ref does not know about" do
      expect(database.baseline_version_for(port: "absent", ref: "2025.06.13")).to be_nil
    end

    it "returns nil for a malformed entry" do
      expect(database.baseline_version_for(port: "broken", ref: "2025.06.13")).to be_nil
    end

    it "memoises per ref" do
      2.times { database.baseline_versions("2025.06.13") }

      expect(Dependabot::SharedHelpers)
        .to have_received(:run_shell_command)
        .with("git show 2025.06.13:versions/baseline.json", cwd: "/opt/vcpkg")
        .once
    end
  end

  describe "#release_tags" do
    it "returns vcpkg release tags oldest first, ignoring other tags" do
      expect(database.release_tags).to eq(%w(2021.04.30 v2024.12.16 2025.06.13))
    end
  end

  describe "#commit_sha_for" do
    it "resolves a ref to a commit" do
      expect(database.commit_sha_for("2025.06.13")).to eq("1" * 40)
    end
  end

  describe "#release_dates_for" do
    let(:git_log) do
      <<~LOG
        #{'1' * 40}\t2024-01-30T12:58:10-08:00
        diff --git a/versions/z-/zlib.json b/versions/z-/zlib.json
        @@ -2,0 +3,4 @@
        +    {
        +      "git-tree": "#{'a' * 40}",
        +      "version": "1.3.1"
        +    },
        #{'2' * 40}\t2023-08-15T09:00:00+00:00
        @@ -2,0 +3,4 @@
        +      "git-tree": "#{'b' * 40}",
      LOG
    end

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(
          "git log --format=tformat:%H%x09%cI --patch --unified=0 -- versions/z-/zlib.json",
          cwd: "/opt/vcpkg"
        )
        .and_return(git_log)
    end

    it "maps each version's git tree to the commit that published it" do
      expect(database.release_dates_for("zlib")).to eq(
        "a" * 40 => Time.parse("2024-01-30T12:58:10-08:00"),
        "b" * 40 => Time.parse("2023-08-15T09:00:00+00:00")
      )
    end
  end
end
