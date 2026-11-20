# typed: false
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "dependabot/dependency_graphers/graph_versions"
require "dependabot/manifest_sets"

RSpec.describe Dependabot::DependencyGraphers::GraphVersions do
  let(:lock_text) { File.read(described_class::LOCK_PATH) }

  def lock(owners)
    JSON.generate({ "schema_version" => 1, "owners" => owners })
  end

  def entry(graph_version: "1", sources: ["lib/grapher.rb"], sources_sha256: "0" * 64)
    { "graph_version" => graph_version, "sources" => sources, "sources_sha256" => sources_sha256 }
  end

  it "is checked in canonical form (run bin/update-manifest-set-graph-versions.rb)" do
    expect(lock_text).to eq(described_class.render(described_class.parse(lock_text)))
  end

  it "locks a graph version for exactly the catalog's owners" do
    owners = Dependabot::ManifestSets.catalog.ecosystems.flat_map { |ecosystem| ecosystem.owners.map(&:id) }

    expect(described_class.entries.keys).to match_array(owners)
  end

  it "reports an owner's graph version" do
    expect(described_class.for("pip")).to eq(described_class.entries.fetch("pip").graph_version)
    expect { described_class.for("unknown") }.to raise_error(ArgumentError, /unknown/)
  end

  it "rejects malformed locks" do
    [
      "[]",
      "{",
      JSON.generate({ "schema_version" => 2, "owners" => { "pip" => entry } }),
      JSON.generate({ "schema_version" => 1, "owners" => { "pip" => entry }, "extra" => true }),
      lock({}),
      lock("pip" => entry.merge("extra" => true)),
      lock("pip" => entry(graph_version: "")),
      lock("pip" => entry(graph_version: 1)),
      lock("pip" => entry(sources: [])),
      lock("pip" => entry(sources: ["/etc/passwd"])),
      lock("pip" => entry(sources: ["lib/../../secret.rb"])),
      lock("pip" => entry(sources_sha256: "abc"))
    ].each do |text|
      expect { described_class.parse(text) }.to raise_error(described_class::InvalidLock), text
    end
  end

  describe ".stale_owners" do
    let(:root) { Dir.mktmpdir }

    after { FileUtils.remove_entry(root) }

    def write(path, content)
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), content)
    end

    it "flags an owner once any of its sources change" do
      write("a/grapher.rb", "graph")
      write("a/parser/one.rb", "one")
      write("b/grapher.rb", "other")
      sources = { "a" => ["a/grapher.rb", "a/parser/*.rb"], "b" => ["b/grapher.rb"] }
      entries = sources.to_h do |owner, globs|
        sha = described_class.sources_sha256(globs, root: root)
        [owner, described_class::Entry.new(graph_version: "1", sources: globs, sources_sha256: sha)]
      end

      expect(described_class.stale_owners(entries: entries, root: root)).to be_empty

      write("a/parser/two.rb", "new file")
      expect(described_class.stale_owners(entries: entries, root: root)).to eq(["a"])
    end

    it "refuses a source pattern that matches nothing" do
      expect { described_class.sources_sha256(["missing/*.rb"], root: root) }
        .to raise_error(described_class::InvalidLock, /matches no files/)
    end
  end
end
