# typed: false
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/manifest_sets/collector"

RSpec.describe Dependabot::ManifestSets::Collector do
  def git(*args)
    stdout, status = Open3.capture2(
      "git", "-C", repo, "-c", "user.name=test", "-c", "user.email=test@example.com", *args
    )
    raise "git #{args.join(' ')} failed" unless status.success?

    stdout.strip
  end

  def commit_files(paths)
    git("init", "--quiet")
    paths.each do |path|
      full = File.join(repo, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, "#{path}\n")
    end
    git("add", "--all")
    git("commit", "--quiet", "-m", "init")
    git("rev-parse", "HEAD")
  end

  def file(path)
    Dependabot::DependencyFile.new(
      name: File.basename(path), directory: "/#{File.dirname(path)}", content: "fetched\n"
    )
  end

  def collect(files, directory:, owner_id:, commit:, catalog: Dependabot::ManifestSets.catalog)
    described_class.collect(
      dependency_files: files,
      repo_contents_path: repo,
      commit: commit,
      directory: directory,
      owner_id: owner_id,
      catalog: catalog
    )
  end

  # A rule-matching fixture basename that selects no owner, so it never changes the expected owner.
  def plain_basename(ecosystem)
    cases = JSON.parse(
      File.read(File.join(Dependabot::ManifestSets::FIXTURES_DIR, "filenames.json"), encoding: "UTF-8")
    )["cases"]
    cases.find do |c|
      c["ecosystem"] == ecosystem.id && !c.key?("catalog") && !ecosystem.selector_basenames.include?(c["basename"]) &&
        ecosystem.rule_matches?(c["basename"]) && !c["basename"].include?(" ")
    end&.fetch("basename") || "requirements.txt"
  end

  let(:repo) { Dir.mktmpdir }

  after { FileUtils.rm_rf(repo) }

  # A catalog where two presence owners can both match, so the matrix also covers ambiguity.
  def self.two_presence_owners
    @two_presence_owners ||= Dependabot::ManifestSets::Catalog.parse(
      JSON.generate(
        "schema_version" => 1,
        "ecosystems" => [{
          "id" => "pypi",
          "path_rules" => [{
            "id" => "r",
            "filename_regex" => "\\A(?:requirements\\.txt|uv\\.lock|poetry\\.lock)\\z",
            "directory" => "parent"
          }],
          "owners" => [
            { "id" => "uv", "when_any_basename" => ["uv.lock"] },
            { "id" => "poetry", "when_any_basename" => ["poetry.lock"] },
            { "id" => "pip", "otherwise" => true }
          ]
        }]
      )
    )
  end

  # Selector completeness: for every combination of selector files in a directory and every package
  # manager's job, the job reports every present selector, and owner selection over its list equals
  # the owner the catalog assigns to the directory.
  { "bundled catalog" => Dependabot::ManifestSets.catalog, "two presence owners" => two_presence_owners }
    .each do |catalog_name, catalog|
    catalog.ecosystems.each do |ecosystem|
      combinations = (0..ecosystem.selector_basenames.length).flat_map do |n|
        ecosystem.selector_basenames.combination(n).to_a
      end
      combinations.each do |present|
        ecosystem.owners.each do |job_owner|
          it "#{catalog_name}: #{ecosystem.id} #{job_owner.id} job with #{present.inspect} reports every selector" do
            plain = plain_basename(ecosystem)
            directory_files = [plain, *present]
            # Selector files elsewhere in the repository must not leak into this directory's list.
            elsewhere = ecosystem.selector_basenames.map { |name| "web/#{name}" }
            commit = commit_files(directory_files.map { |name| "api/#{name}" } + elsewhere)
            # The job reads its own manifest and, when it owns one, its own selector file.
            read = [plain, *(present & job_owner.when_any_basename)].map { |name| file("api/#{name}") }

            inputs = collect(read, directory: "/api", owner_id: job_owner.id, commit: commit, catalog: catalog)

            expect(inputs.resolved?).to be(true)
            expect(inputs.files.map(&:path)).to eq(directory_files.map { |name| "api/#{name}" }.sort_by(&:b))
            expect(inputs.files.map(&:blob_oid)).to eq(inputs.files.map { |f| git("rev-parse", "#{commit}:#{f.path}") })
            reported = inputs.files.map { |f| File.basename(f.path) }
            served = ecosystem.select_owner(directory_files)
            selected = ecosystem.select_owner(reported)
            expect([selected.owner&.id, selected.ambiguous]).to eq([served.owner&.id, served.ambiguous])

            descriptor = described_class.describe(
              dependency_files: read,
              repo_contents_path: repo,
              commit: commit,
              directory: "/api",
              owner_id: job_owner.id,
              graph_version: "1",
              catalog: catalog
            )
            expect(descriptor.reason).to eq(served.ambiguous ? "ambiguous_owner" : nil)
            pairs = ->(files) { files.map { |f| [f.path, f.blob_oid] } }
            expect(pairs.call(descriptor.files)).to eq(served.ambiguous ? [] : pairs.call(inputs.files))
          end
        end
      end
    end
  end

  it "covers every package manager in the bundled catalog" do
    owners = Dependabot::ManifestSets.catalog.ecosystems.flat_map { |e| e.owners.map(&:id) }
    expect(owners).to contain_exactly("pip", "uv", "go_modules")
  end

  it "adds a selector the pip job did not read in the repository root" do
    commit = commit_files(%w(requirements.txt uv.lock))

    inputs = collect([file("./requirements.txt")], directory: "/", owner_id: "pip", commit: commit)

    expect(inputs.files.map(&:path)).to eq(%w(requirements.txt uv.lock))
  end

  it "matches selectors case-sensitively" do
    commit = commit_files(%w(api/requirements.txt api/UV.lock))

    inputs = collect([file("api/requirements.txt")], directory: "/api", owner_id: "pip", commit: commit)

    expect(inputs.files.map(&:path)).to eq(["api/requirements.txt"])
  end

  it "reports only the grapher's inputs for a package manager the catalog does not cover" do
    commit = commit_files(%w(Gemfile uv.lock))

    inputs = collect([file("./Gemfile")], directory: "/", owner_id: "bundler", commit: commit)

    expect(inputs.files.map(&:path)).to eq(["Gemfile"])
  end

  it "is unresolvable when the directory cannot be listed" do
    commit = commit_files(%w(api/requirements.txt))

    inputs = collect([file("api/requirements.txt")], directory: "/api/../api", owner_id: "pip", commit: commit)

    expect(inputs.unresolvable_reason).to eq(Dependabot::ManifestSets::Inputs::UNKNOWN_PROVENANCE)
  end

  it "keeps an unresolvable grapher result" do
    commit = commit_files(%w(api/requirements.txt))

    inputs = collect([file("api/missing.txt")], directory: "/api", owner_id: "pip", commit: commit)

    expect(inputs.resolved?).to be(false)
  end

  describe ".describe" do
    def describe_set(files, directory:, owner_id:, commit:, catalog: Dependabot::ManifestSets.catalog, reason: nil)
      described_class.describe(
        dependency_files: files,
        repo_contents_path: repo,
        commit: commit,
        directory: directory,
        owner_id: owner_id,
        graph_version: "7",
        unresolvable_reason: reason,
        catalog: catalog
      )
    end

    def delete_and_commit(*paths)
      git("rm", "--quiet", "-r", *paths)
      git("commit", "--quiet", "-m", "delete")
      git("rev-parse", "HEAD")
    end

    it "is present with every input, its owner and graph version" do
      commit = commit_files(%w(api/requirements.in api/requirements.txt api/uv.lock))

      descriptor = describe_set(
        [file("api/requirements.in"), file("api/requirements.txt")], directory: "/api/", owner_id: "pip", commit: commit
      )

      expect(descriptor.to_h).to eq(
        "schema_version" => 1,
        "ecosystem" => "pypi",
        "directory" => "api",
        "owner" => "pip",
        "graph_version" => "7",
        "state" => "present",
        "files" => %w(api/requirements.in api/requirements.txt api/uv.lock).map do |path|
          { "path" => path, "blob_oid" => git("rev-parse", "#{commit}:#{path}") }
        end
      )
    end

    it "is absent once the last rule-matching file is deleted" do
      commit_files(%w(api/requirements.txt api/README.md web/requirements.txt))
      commit = delete_and_commit("api/requirements.txt")

      descriptor = describe_set([], directory: "/api", owner_id: "uv", commit: commit)

      expect(descriptor.to_h).to include("state" => "absent", "files" => [], "directory" => "api", "owner" => "uv")
    end

    it "is absent when the directory no longer exists" do
      commit_files(%w(api/requirements.txt web/requirements.txt))
      commit = delete_and_commit("api")

      expect(describe_set([], directory: "/api", owner_id: "pip", commit: commit).state)
        .to eq(Dependabot::ManifestSets::Descriptor::State::Absent)
    end

    it "is absent in the repository root" do
      commit = commit_files(%w(README.md api/requirements.txt))

      expect(describe_set([], directory: "/", owner_id: "pip", commit: commit).to_h)
        .to include("directory" => ".", "state" => "absent", "files" => [])
    end

    it "reports nothing for an empty result while rule-matching files remain" do
      commit = commit_files(%w(api/uv.lock api/pyproject.toml))

      expect(describe_set([], directory: "/api", owner_id: "pip", commit: commit)).to be_nil
    end

    it "reports nothing for a package manager the catalog does not cover" do
      commit = commit_files(%w(Gemfile))

      expect(describe_set([file("./Gemfile")], directory: "/", owner_id: "bundler", commit: commit)).to be_nil
    end

    it "reports nothing for a directory outside the repository" do
      commit = commit_files(%w(api/requirements.txt))

      expect(describe_set([], directory: "/api/../..", owner_id: "pip", commit: commit)).to be_nil
    end

    it "is unresolvable with the grapher's reason and no file list" do
      commit = commit_files(%w(go.mod go.work))

      descriptor = describe_set(
        [file("./go.mod")],
        directory: "/",
        owner_id: "go_modules",
        commit: commit,
        reason: Dependabot::ManifestSets::Descriptor::WORKSPACE
      )

      expect(descriptor.to_h).to eq(
        "schema_version" => 1,
        "ecosystem" => "golang",
        "directory" => ".",
        "owner" => "go_modules",
        "graph_version" => "7",
        "state" => "unresolvable",
        "reason" => "workspace"
      )
    end

    it "is unresolvable when no file directly in the directory defines the set" do
      commit = commit_files(%w(requirements/production.txt))

      descriptor = describe_set([file("requirements/production.txt")], directory: "/", owner_id: "pip", commit: commit)

      expect(descriptor.to_h).to include(
        "directory" => ".", "state" => "unresolvable", "reason" => Dependabot::ManifestSets::Descriptor::UNKNOWN_PROVENANCE
      )
    end

    it "reports input_limit for too many inputs without looking them up" do
      commit = commit_files(%w(api/requirements.txt))
      files = Array.new(Dependabot::ManifestSets::Descriptor::MAX_FILES + 1) { |i| file("api/r#{i}.txt") }
      allow(Dependabot::ManifestSets::Inputs).to receive(:resolve).and_call_original

      descriptor = describe_set(files, directory: "/api", owner_id: "pip", commit: commit)

      expect(descriptor.reason).to eq(Dependabot::ManifestSets::Descriptor::INPUT_LIMIT)
      expect(Dependabot::ManifestSets::Inputs).not_to have_received(:resolve)
    end

    it "reports input_limit for an over-long input path without looking it up" do
      commit = commit_files(%w(api/requirements.txt))
      long_name = "api/#{'r' * Dependabot::ManifestSets::Descriptor::MAX_PATH_BYTES}.txt"

      descriptor = describe_set([file(long_name)], directory: "/api", owner_id: "pip", commit: commit)

      expect(descriptor.reason).to eq(Dependabot::ManifestSets::Descriptor::INPUT_LIMIT)
    end

    it "is unresolvable when an input has no repository blob" do
      commit = commit_files(%w(api/requirements.txt))

      descriptor = describe_set([file("api/missing.txt")], directory: "/api", owner_id: "pip", commit: commit)

      expect(descriptor.reason).to eq(Dependabot::ManifestSets::Descriptor::UNKNOWN_PROVENANCE)
    end

    it "is unresolvable rather than picking an owner when two presence owners match" do
      commit = commit_files(%w(api/requirements.txt api/uv.lock api/poetry.lock))

      descriptor = describe_set(
        [file("api/requirements.txt")],
        directory: "/api",
        owner_id: "pip",
        commit: commit,
        catalog: self.class.two_presence_owners
      )

      expect(descriptor.reason).to eq(Dependabot::ManifestSets::Descriptor::AMBIGUOUS_OWNER)
    end

    it "is unresolvable when an owner-selection file is a symlink" do
      commit_files(%w(api/requirements.txt shared/uv.lock))
      File.symlink("../shared/uv.lock", File.join(repo, "api", "uv.lock"))
      git("add", "--all")
      git("commit", "--quiet", "-m", "link")

      descriptor = describe_set(
        [file("api/requirements.txt")], directory: "/api", owner_id: "pip", commit: git("rev-parse", "HEAD")
      )

      expect(descriptor.to_h).to include("state" => "unresolvable", "reason" => "unknown_provenance")
    end

    it "is not absent while a symlinked rule-matching file remains" do
      commit_files(%w(api/requirements.txt shared/requirements.txt))
      git("rm", "--quiet", "api/requirements.txt")
      FileUtils.mkdir_p(File.join(repo, "api"))
      File.symlink("../shared/requirements.txt", File.join(repo, "api", "requirements.txt"))
      git("add", "--all")
      git("commit", "--quiet", "-m", "link")

      expect(describe_set([], directory: "/api", owner_id: "pip", commit: git("rev-parse", "HEAD"))).to be_nil
    end
  end

  it "reports unknown provenance when an owner-selection file is a symlink" do
    commit_files(["api/requirements.txt", "shared/uv.lock"])
    File.symlink("../shared/uv.lock", File.join(repo, "api", "uv.lock"))
    git("add", "--all")
    git("commit", "--quiet", "-m", "link")

    inputs = collect(
      [file("api/requirements.txt")], directory: "/api", owner_id: "pip", commit: git("rev-parse", "HEAD")
    )

    expect(inputs.resolved?).to be(false)
    expect(inputs.unresolvable_reason).to eq(Dependabot::ManifestSets::Inputs::UNKNOWN_PROVENANCE)
  end
end
