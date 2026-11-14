# typed: false
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/manifest_sets/inputs"

RSpec.describe Dependabot::ManifestSets::Inputs do
  def git(*args)
    stdout, status = Open3.capture2(
      "git",
      "-C",
      repo,
      "-c",
      "user.name=test",
      "-c",
      "user.email=test@example.com",
      *args
    )
    raise "git #{args.join(' ')} failed" unless status.success?

    stdout.strip
  end

  def write(path, content)
    full = File.join(repo, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def file(name, directory: "/", content: "fetched content\n")
    Dependabot::DependencyFile.new(name: name, directory: directory, content: content)
  end

  let(:repo) { Dir.mktmpdir }
  let(:commit) do
    git("init", "--quiet")
    write("requirements.txt", "requests==2.32.5\n")
    write("B.txt", "upper\n")
    write("api/go.mod", "module example.com/api\n")
    git("add", "--all")
    git("commit", "--quiet", "-m", "init")
    git("rev-parse", "HEAD")
  end

  after { FileUtils.rm_rf(repo) }

  describe ".resolve" do
    it "reports each file's original blob at the commit, deduplicated and sorted by bytes" do
      inputs = described_class.resolve(
        dependency_files: [
          file("requirements.txt"), file("go.mod", directory: "/api"), file("B.txt"), file("requirements.txt")
        ],
        repo_contents_path: repo,
        commit: commit
      )

      expect(inputs.resolved?).to be(true)
      expect(inputs.files.map(&:path)).to eq(%w(B.txt api/go.mod requirements.txt))
      expect(inputs.files.map(&:blob_oid)).to eq(
        inputs.files.map { |input| git("rev-parse", "#{commit}:#{input.path}") }
      )
      expect(inputs.files.map(&:blob_oid)).to all(match(/\A\h{40}\z/))
    end

    it "describes the committed content rather than the fetched content" do
      committed = git("rev-parse", "#{commit}:requirements.txt")
      write("requirements.txt", "rewritten during resolution\n")
      expect(git("hash-object", "requirements.txt")).not_to eq(committed)

      inputs = described_class.resolve(
        dependency_files: [file("requirements.txt", content: "rewritten during resolution\n")],
        repo_contents_path: repo,
        commit: commit
      )

      expect(inputs.files.map(&:blob_oid)).to eq([committed])
    end

    it "is resolved with no files when there are no inputs" do
      inputs = described_class.resolve(dependency_files: [], repo_contents_path: repo, commit: commit)

      expect(inputs.resolved?).to be(true)
      expect(inputs.files).to be_empty
    end

    it "is unresolvable without a checkout" do
      inputs = described_class.resolve(
        dependency_files: [file("requirements.txt")], repo_contents_path: nil, commit: "0" * 40
      )

      expect(inputs.resolved?).to be(false)
      expect(inputs.unresolvable_reason).to eq(described_class::UNKNOWN_PROVENANCE)
      expect(inputs.files).to be_empty
    end

    it "is unresolvable when the commit is not a full object ID" do
      commit

      inputs = described_class.resolve(
        dependency_files: [file("requirements.txt")], repo_contents_path: repo, commit: "--output=#{repo}/x"
      )

      expect(inputs.unresolvable_reason).to eq(described_class::UNKNOWN_PROVENANCE)
      expect(File.exist?(File.join(repo, "x"))).to be(false)
    end

    it "matches file names literally rather than as patterns" do
      commit
      write("f*.txt", "literal\n")
      git("add", "--all")
      git("commit", "--quiet", "-m", "pattern-like name")
      head = git("rev-parse", "HEAD")

      literal = described_class.resolve(dependency_files: [file("f*.txt")], repo_contents_path: repo, commit: head)
      pattern = described_class.resolve(dependency_files: [file("f?.txt")], repo_contents_path: repo, commit: head)

      expect(literal.files.map(&:blob_oid)).to eq([git("rev-parse", "#{head}:f*.txt")])
      expect(pattern.resolved?).to be(false)
    end

    it "is unresolvable rather than partial when any file has no blob at the commit" do
      inputs = described_class.resolve(
        dependency_files: [file("requirements.txt"), file("generated.lock")],
        repo_contents_path: repo,
        commit: commit
      )

      expect(inputs.unresolvable_reason).to eq(described_class::UNKNOWN_PROVENANCE)
      expect(inputs.files).to be_empty
    end

    it "is unresolvable when a path names a directory" do
      inputs = described_class.resolve(
        dependency_files: [file("api")], repo_contents_path: repo, commit: commit
      )

      expect(inputs.resolved?).to be(false)
    end

    it "is unresolvable for an unknown commit" do
      commit
      inputs = described_class.resolve(
        dependency_files: [file("requirements.txt")], repo_contents_path: repo, commit: "f" * 40
      )

      expect(inputs.resolved?).to be(false)
    end

    context "with symlinked inputs" do
      let(:commit) do
        git("init", "--quiet")
        write("api/base.txt", "requests==2.32.5\n")
        write("base.txt", "unrelated==1.0.0\n")
        File.symlink("base.txt", File.join(repo, "api", "requirements.txt"))
        File.symlink("api", File.join(repo, "linked"))
        git("add", "--all")
        git("commit", "--quiet", "-m", "init")
        git("rev-parse", "HEAD")
      end

      it "is unresolvable when an input is itself a symlink in the commit" do
        inputs = described_class.resolve(
          dependency_files: [file("requirements.txt", directory: "/api")], repo_contents_path: repo, commit: commit
        )

        expect(inputs.unresolvable_reason).to eq(described_class::UNKNOWN_PROVENANCE)
      end

      it "is unresolvable when the fetcher reports a symlink target" do
        symlinked = Dependabot::DependencyFile.new(
          name: "requirements.txt",
          directory: "/api",
          content: "requests==2.32.5\n",
          type: "symlink",
          symlink_target: "api/base.txt"
        )

        inputs = described_class.resolve(dependency_files: [symlinked], repo_contents_path: repo, commit: commit)

        expect(inputs.unresolvable_reason).to eq(described_class::UNKNOWN_PROVENANCE)
      end

      it "is unresolvable when an input is reached through a symlinked directory" do
        inputs = described_class.resolve(
          dependency_files: [file("base.txt", directory: "/linked")], repo_contents_path: repo, commit: commit
        )

        expect(inputs.unresolvable_reason).to eq(described_class::UNKNOWN_PROVENANCE)
      end
    end

    it "rejects paths that cannot be looked up safely" do
      inputs = described_class.resolve(
        dependency_files: [file("requirements.txt"), file("evil\nHEAD:requirements.txt")],
        repo_contents_path: repo,
        commit: commit
      )

      expect(inputs.resolved?).to be(false)
    end
  end
end
