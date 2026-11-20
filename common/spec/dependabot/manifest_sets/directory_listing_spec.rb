# typed: false
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "spec_helper"
require "dependabot/manifest_sets/directory_listing"

RSpec.describe Dependabot::ManifestSets::DirectoryListing do
  def git(*args)
    stdout, status = Open3.capture2(
      "git", "-C", repo, "-c", "user.name=test", "-c", "user.email=test@example.com", *args
    )
    raise "git #{args.join(' ')} failed" unless status.success?

    stdout.strip
  end

  def write(path, content = "#{path}\n")
    full = File.join(repo, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def oid(path)
    git("rev-parse", "#{commit}:#{path}")
  end

  let(:repo) { Dir.mktmpdir }
  let(:commit) do
    git("init", "--quiet")
    write("requirements.txt")
    write("api/uv.lock")
    write("api/requirements.txt")
    write("api/nested/uv.lock")
    write("a*b/uv.lock")
    write("ab/pyproject.toml")
    git("add", "--all")
    git("commit", "--quiet", "-m", "init")
    git("rev-parse", "HEAD")
  end

  after { FileUtils.rm_rf(repo) }

  describe ".normalize" do
    it "maps job directories to canonical set directories" do
      expect(described_class.normalize("/")).to eq(".")
      expect(described_class.normalize("")).to eq(".")
      expect(described_class.normalize(".")).to eq(".")
      expect(described_class.normalize("/api/")).to eq("api")
      expect(described_class.normalize("/api/v1")).to eq("api/v1")
      expect(described_class.normalize("api")).to eq("api")
    end

    it "rejects traversal and empty components instead of aliasing them" do
      ["/../api", "/api/..", "/./api", "//api", "/api//v1", "/a\0b", "/a\nb", "/\xFF".b.force_encoding("UTF-8")]
        .each { |directory| expect(described_class.normalize(directory)).to be_nil, directory.inspect }
    end
  end

  describe ".read" do
    it "lists symlinks apart from regular files" do
      commit
      File.symlink("requirements.txt", File.join(repo, "api", "requirements-dev.txt"))
      git("add", "--all")
      git("commit", "--quiet", "-m", "link")
      head = git("rev-parse", "HEAD")

      listing = described_class.read(repo_contents_path: repo, commit: head, directory: "api")

      expect(listing.blobs.keys).to contain_exactly("requirements.txt", "uv.lock")
      expect(listing.symlinks).to eq(["requirements-dev.txt"])
    end

    it "lists only blobs directly in the directory, with their blob OIDs" do
      listing = described_class.read(repo_contents_path: repo, commit: commit, directory: "api")

      expect(listing.directory).to eq("api")
      expect(listing.blobs).to eq(
        "requirements.txt" => oid("api/requirements.txt"),
        "uv.lock" => oid("api/uv.lock")
      )
    end

    it "lists the repository root" do
      listing = described_class.read(repo_contents_path: repo, commit: commit, directory: ".")

      expect(listing.blobs).to eq("requirements.txt" => oid("requirements.txt"))
    end

    it "treats directory names literally rather than as patterns" do
      listing = described_class.read(repo_contents_path: repo, commit: commit, directory: "a*b")

      expect(listing.blobs.keys).to eq(["uv.lock"])
    end

    it "reports a directory that does not exist at the commit as empty" do
      listing = described_class.read(repo_contents_path: repo, commit: commit, directory: "gone")

      expect(listing.blobs).to eq({})
    end

    it "returns nil when Git cannot answer" do
      expect(described_class.read(repo_contents_path: repo, commit: "0" * 40, directory: "api")).to be_nil
      expect(described_class.read(repo_contents_path: repo, commit: "--help", directory: "api")).to be_nil
      expect(described_class.read(repo_contents_path: repo, commit: commit, directory: "/api")).to be_nil
    end
  end
end
