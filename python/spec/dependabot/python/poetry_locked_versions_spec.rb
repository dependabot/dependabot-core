# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python/file_parser"
require "dependabot/python/file_updater"
require "dependabot/python/poetry_locked_versions"
require "dependabot/python/update_checker"

RSpec.describe Dependabot::Python::PoetryLockedVersions do
  let(:py39) { 'python_version == "3.9"' }
  let(:py310) { 'python_version >= "3.10"' }
  let(:project) do
    Dependabot::Python::PoetryProject.new(
      {
        "groups_and_markers_locked" => groups_and_markers_locked,
        "locked" => locked_packages
      }
    )
  end
  let(:groups_and_markers_locked) { true }
  let(:locked_packages) { [locked("2.32.3", py39, "3.9"), locked("2.33.0", py310, "3.10")] }

  def locked(version, marker, min_python, **overrides)
    {
      "name" => "requests", "version" => version, "groups" => ["main"], "groups_from_lockfile" => true,
      "markers" => { "main" => marker }, "min_python" => min_python, "optional" => false
    }.merge(overrides)
  end

  describe ".for" do
    it "covers a package locked once per marker" do
      expect(described_class.for(project, "Requests")).to be_a(described_class)
    end

    context "when the package is locked once" do
      let(:locked_packages) { [locked("2.32.3", nil, "3.9")] }

      it { expect(described_class.for(project, "requests")).to be_nil }
    end

    context "when the lockfile is older than 2.1" do
      let(:groups_and_markers_locked) { false }

      it { expect(described_class.for(project, "requests")).to be_nil }
    end

    context "when a locked version is optional" do
      let(:locked_packages) { [locked("2.32.3", py39, "3.9", "optional" => true), locked("2.33.0", py310, "3.10")] }

      it { expect(described_class.for(project, "requests")).to be_nil }
    end
  end

  describe ".hold_pins" do
    it "pins each locked version of other packages where it is" do
      pins = described_class.hold_pins(project, except: ["urllib3"])
      expect(pins.map { |pin| [pin.name, pin.version, pin.markers] }).to eq(
        [["requests", "2.32.3", { "main" => py39 }], ["requests", "2.33.0", { "main" => py310 }]]
      )
    end

    it "skips the packages being updated" do
      expect(described_class.hold_pins(project, except: ["Requests"])).to eq([])
    end
  end

  describe ".pins_applied?" do
    let(:pins) { described_class.hold_pins(project, except: []) }

    it { expect(described_class.pins_applied?(pins, { "requests" => %w(2.33.0 2.32.3) })).to be(true) }
    it { expect(described_class.pins_applied?(pins, { "requests" => %w(2.33.0) })).to be(false) }
  end

  describe "#targets" do
    subject(:targets) do
      described_class.for(project, "requests").targets(requirements: requirements) do |min_python|
        releases.fetch(min_python).map { |v| Dependabot::Python::Version.new(v) }
      end
    end

    let(:requirements) { ["^2.32.3"] }
    # What the latest version finder returns for each Python version.
    let(:releases) do
      {
        "3.9" => %w(2.31.0 2.32.3 2.32.4 2.32.5),
        "3.10" => %w(2.31.0 2.32.3 2.32.5 2.33.0 2.34.0 3.0.0)
      }
    end

    it "picks the newest release each locked version's Python supports, within the requirement" do
      expect(targets.map(&:to_metadata)).to eq(
        [
          { "previous_version" => "2.32.3", "version" => "2.32.5", "markers" => { "main" => py39 } },
          { "previous_version" => "2.33.0", "version" => "2.34.0", "markers" => { "main" => py310 } }
        ]
      )
    end

    context "when the newest allowed release is older than what's locked" do
      let(:requirements) { ["<2.33"] }

      it "keeps the locked version" do
        expect(targets.map(&:version)).to eq(%w(2.32.5 2.33.0))
      end
    end

    it "round-trips through dependency metadata" do
      dependency = Dependabot::Dependency.new(
        name: "requests",
        version: "2.34.0",
        requirements: [],
        package_manager: "pip",
        metadata: { described_class::METADATA_KEY => targets.map(&:to_metadata) }
      )

      expect(described_class.targets_from(dependency).map(&:to_metadata)).to eq(targets.map(&:to_metadata))
    end
  end

  # requests 2.33 dropped Python 3.9, so the fixture locks 2.32.3 for 3.9 and
  # 2.33.0 for 3.10+. Ruby reads trimmed PyPI indexes; the native helper
  # resolves against live PyPI.
  describe "updating a package locked at several versions, end to end" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "poetry_native_stale_multiple_locked_versions.toml")
        ),
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: fixture("poetry_locks", "poetry_native_stale_multiple_locked_versions.lock")
        )
      ]
    end
    let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: "/") }
    let(:parsed) do
      Dependabot::Python::FileParser.new(dependency_files: files, source: source).parse
    end

    def checker_for(name, ignored_versions: [])
      Dependabot::Python::UpdateChecker.new(
        dependency: parsed.find { |d| d.name == name },
        dependency_files: files,
        credentials: [],
        ignored_versions: ignored_versions
      )
    end

    def update(dependencies)
      Dependabot::Python::FileUpdater.new(dependencies: dependencies, dependency_files: files, credentials: [])
                                     .updated_dependency_files
    end

    def locked_requests(lockfile)
      Dependabot::Python::FileParser::PoetryLock.from_content(lockfile.content)
                                                .records_for("requests", &:itself)
                                                .map { |record| [record.version, record.scope.markers_for("main")] }
    end

    before do
      Dependabot::Experiments.register(:enable_native_poetry_helper, true)
      %w(requests urllib3).each do |name|
        stub_request(:get, "https://pypi.org/simple/#{name}/")
          .to_return(status: 200, body: fixture("pypi", "pypi_simple_response_#{name}_python_split.html"))
      end
      stub_request(:get, "https://pypi.org/pypi/stale-multiple-locked-versions/json/").to_return(status: 404)
    end

    it "moves each locked version to its own target" do
      # Ignore rules apply to every locked version.
      updated = checker_for("requests", ignored_versions: [">= 2.34.1"]).updated_dependencies(
        requirements_to_unlock: :own
      )

      expect(updated.map { |d| [d.version, d.previous_version] }).to eq([%w(2.34.0 2.32.3)])
      expect(described_class.targets_from(updated.first).map { |t| [t.previous_version, t.version] })
        .to eq([%w(2.32.3 2.32.5), %w(2.33.0 2.34.0)])

      files_after = update(updated)
      expect(files_after.map(&:name)).to eq(["poetry.lock"])
      expect(locked_requests(files_after.first)).to eq(
        [["2.32.5", ["(#{py39})"]], ["2.34.0", ["(#{py310})"]]]
      )
      expect(files_after.first.content).to include("name = \"urllib3\"\nversion = \"2.3.0\"")
    end

    it "keeps another package's locked versions when updating something else" do
      updated = checker_for("urllib3").updated_dependencies(requirements_to_unlock: :own)
      expect(updated.map(&:version)).to eq(["2.5.0"])

      lockfile = update(updated).find { |f| f.name == "poetry.lock" }
      expect(lockfile.content).to include("name = \"urllib3\"\nversion = \"2.5.0\"")
      expect(locked_requests(lockfile).map(&:first)).to eq(%w(2.32.3 2.33.0))
    end

    it "declines security updates" do
      checker = checker_for("requests")
      expect(checker.send(:resolver).resolvable?(version: Dependabot::Python::Version.new("2.33.0"))).to be(false)
    end
  end
end
