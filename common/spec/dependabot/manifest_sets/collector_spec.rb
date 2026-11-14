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
  two_presence_owners = Dependabot::ManifestSets::Catalog.parse(
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
