# typed: strict
# frozen_string_literal: true

# ScatteredLet moves Sorbet signatures away from their let declarations.
# rubocop:disable RSpec/ScatteredLet

require "spec_helper"
require "dependabot/cargo/graph_transition_policy"
require "dependabot/cargo/lockfile_graph"

RSpec.describe Dependabot::Cargo::GraphTransitionPolicy do
  extend T::Sig

  sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
  let(:old) { package("example", "2.0.0") }
  sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Result) }
  let(:result) { described_class.evaluate(facts: facts, intents: intents) }
  sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
  let(:target) { package("example", "3.0.0") }
  sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
  let(:lower) { package("example", "1.0.0") }
  sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
  let(:parent) { package("parent", "1.0.0", nil) }
  sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
  let(:other_parent) { package("other", "1.0.0", nil) }
  sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
  let(:before_packages) { [parent, other_parent, lower, old, target] }
  sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
  let(:after_packages) { [parent, other_parent, lower, target] }
  sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
  let(:before_edges) { [edge(parent, old), edge(other_parent, lower)] }
  sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
  let(:after_edges) { [edge(parent, target), edge(other_parent, lower)] }
  sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Intent]) }
  let(:intents) { [Dependabot::Cargo::GraphTransitionPolicy::Intent.new(previous: old, target: target)] }
  sig { returns(T::Hash[String, Object]) }
  let(:facts) do
    Dependabot::Cargo::LockfileGraph.facts(
      snapshots: {
        "before" => lockfile(before_packages, before_edges),
        "after" => lockfile(after_packages, after_edges)
      }
    )
  end

  sig do
    params(name: String, version: String, source: T.nilable(String))
      .returns(Dependabot::Cargo::GraphTransitionPolicy::Package)
  end
  def package(name, version, source = "registry+https://github.com/rust-lang/crates.io-index")
    Dependabot::Cargo::GraphTransitionPolicy::Package.new(name: name, version: version, source: source)
  end

  sig do
    params(
      from: Dependabot::Cargo::GraphTransitionPolicy::Package,
      to: Dependabot::Cargo::GraphTransitionPolicy::Package,
      kind: String
    ).returns(Dependabot::Cargo::GraphTransitionPolicy::Edge)
  end
  def edge(from, to, kind = "dependency")
    Dependabot::Cargo::GraphTransitionPolicy::Edge.new(from: from, to: to, kind: kind)
  end

  sig do
    params(
      packages: T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package],
      edges: T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]
    ).returns(Dependabot::DependencyFile)
  end
  def lockfile(packages, edges)
    entries = packages.map do |pkg|
      outgoing = edges.select { |item| item.from.key == pkg.key }
      dependencies = outgoing.select { |item| item.kind == "dependency" }.map { |item| reference(item.to).inspect }
      replacement = outgoing.find { |item| item.kind == "replacement" }
      [
        "[[package]]", "name = #{pkg.name.inspect}", "version = #{pkg.version.inspect}",
        ("source = #{pkg.source.inspect}" if pkg.source),
        "dependencies = [#{dependencies.join(', ')}]",
        ("replace = #{reference(replacement.to).inspect}" if replacement)
      ].compact.join("\n")
    end
    Dependabot::DependencyFile.new(name: "Cargo.lock", content: "version = 3\n\n#{entries.join("\n\n")}\n")
  end

  sig { params(pkg: Dependabot::Cargo::GraphTransitionPolicy::Package).returns(String) }
  def reference(pkg)
    "#{pkg.name} #{pkg.version}#{" (#{pkg.source})" if pkg.source}"
  end

  it "accepts {1,2,3}->{1,3} only with an edge to the existing target" do
    expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Accepted)
    expect(result.reasons.map(&:code)).to include("edge_retargeted")
    expect(T.must(result.reasons.first).observed&.key).to eq(target.key)
  end

  context "when the old edge moves to a retained lower version" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { [edge(parent, lower), edge(other_parent, lower)] }

    it "rejects even though the requested target is still present" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Rejected)
      expect(result.reasons.map(&:code)).to include("edge_downgrade")
    end
  end

  context "when the target is introduced" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
    let(:before_packages) { [parent, other_parent, lower, old] }

    it "accepts the proven incoming-edge transition" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Accepted)
    end
  end

  context "with several incoming edges" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:before_edges) { [edge(parent, old), edge(other_parent, old)] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { [edge(parent, target), edge(other_parent, target)] }

    it "proves both transitions" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Accepted)
      expect(result.reasons.count { |reason| reason.code == "edge_retargeted" }).to eq(2)
    end

    context "when one edge downgrades" do
      sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
      let(:after_edges) { [edge(parent, target), edge(other_parent, lower)] }

      it "rejects the whole group" do
        expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Rejected)
      end
    end
  end

  context "with an explicitly selected split graph" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
    let(:after_packages) { before_packages }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:before_edges) { [edge(parent, old), edge(other_parent, old)] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { [edge(parent, target), edge(other_parent, old)] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Intent]) }
    let(:intents) { [Dependabot::Cargo::GraphTransitionPolicy::Intent.new(previous: old, target: target, parents: [parent])] }

    it "accepts while leaving the old version for an unselected parent" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Accepted)
    end

    context "without a parent selection" do
      sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Intent]) }
      let(:intents) { [Dependabot::Cargo::GraphTransitionPolicy::Intent.new(previous: old, target: target)] }

      it "reports an unfulfilled edge rather than treating package presence as success" do
        expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
        expect(result.reasons.map(&:code)).to include("unchanged_edge")
      end
    end
  end

  context "when nothing changed" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
    let(:after_packages) { before_packages }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { before_edges }

    it "does not claim the requested update succeeded" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
      expect(result.reasons.map(&:code)).to include("unchanged_edge")
    end

    context "with an explicit no-op intent" do
      sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
      let(:target) { old }
      sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
      let(:before_packages) { [parent, other_parent, lower, old] }

      it "accepts the unchanged selected edge" do
        expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Accepted)
        expect(result.reasons.map(&:code)).to include("no_op")
      end

      context "when a competing destination appears" do
        sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
        let(:after_edges) { super() + [edge(parent, lower)] }

        it "does not label the changed graph a proven no-op" do
          expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
          expect(result.reasons.map(&:code)).to include("ambiguous_destination")
        end
      end
    end
  end

  context "when a parent updates in the same group" do
    sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
    let(:new_parent) { package("parent", "2.0.0", nil) }
    sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
    let(:root) { package("root", "1.0.0", nil) }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
    let(:before_packages) { super() + [root] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
    let(:after_packages) { [root, new_parent, other_parent, lower, target] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:before_edges) { super() + [edge(root, parent)] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { [edge(root, new_parent), edge(new_parent, target), edge(other_parent, lower)] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Intent]) }
    let(:intents) do
      super() + [Dependabot::Cargo::GraphTransitionPolicy::Intent.new(previous: parent, target: new_parent)]
    end

    it "correlates the parent using its exact group intent" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Accepted)
    end

    context "when both parent identities remain" do
      sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
      let(:after_packages) { super() + [parent] }

      it "does not guess which parent inherited the edge" do
        expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
        expect(result.reasons.map(&:code)).to include("parent_uncorrelated")
      end
    end
  end

  context "with the same name and version from a different source" do
    sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
    let(:duplicate) { package("example", "3.0.0", "registry+https://example.com/index") }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
    let(:after_packages) { super() + [duplicate] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { [edge(parent, duplicate), edge(other_parent, lower)] }

    it "does not equate the duplicate with the target" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
      expect(result.reasons.map(&:code)).to include("source_changed")
    end
  end

  context "with replacement edges" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:before_edges) { [edge(parent, old, "replacement"), edge(other_parent, lower)] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { [edge(parent, target, "replacement"), edge(other_parent, lower)] }

    it "checks replacement destinations separately from dependency edges" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Accepted)
    end

    context "when the edge kind changes" do
      sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
      let(:after_edges) { [edge(parent, target), edge(other_parent, lower)] }

      it "reports the missing replacement proof" do
        expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
        expect(result.reasons.map(&:code)).to include("destination_unproven")
      end
    end
  end

  context "when Cargo selects another higher version" do
    sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
    let(:alternative) { package("example", "2.5.0") }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
    let(:after_packages) { super() + [alternative] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { [edge(parent, alternative), edge(other_parent, lower)] }

    it "records the observed version but cannot prove manifest compatibility" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
      expect(result.reasons.map(&:code)).to include("alternative_version")
      expect(T.must(result.reasons.first).observed&.key).to eq(alternative.key)
    end
  end

  context "when a target edge and a new lower edge both appear" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { [edge(parent, target), edge(parent, lower), edge(other_parent, lower)] }

    it "does not claim a unique transition" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
      expect(result.reasons.map(&:code)).to include("ambiguous_destination")
    end
  end

  context "when the old and target edges both remain for the selected parent" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
    let(:after_packages) { before_packages }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { super() + [edge(parent, old)] }

    it "cannot prove that the selected old edge moved" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
      expect(result.reasons.map(&:code)).to include("unchanged_edge")
    end
  end

  context "when the old parent disappears without a group intent" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Package]) }
    let(:after_packages) { [other_parent, lower, target] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { [edge(other_parent, lower)] }

    it "does not use global target presence as an edge proof" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
      expect(result.reasons.map(&:code)).to include("parent_uncorrelated")
    end
  end

  context "when the requested target itself downgrades" do
    sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
    let(:target) { package("example", "1.5.0") }

    it "rejects the update intent" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Rejected)
      expect(result.reasons.map(&:code)).to include("requested_downgrade")
    end
  end

  context "with prerelease versions" do
    sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
    let(:old) { package("example", "3.0.0-beta.2") }
    sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
    let(:target) { package("example", "3.0.0-beta.10") }

    it "uses Cargo version precedence rather than lexical ordering" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Accepted)
    end
  end

  context "with distinct build metadata" do
    sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
    let(:old) { package("example", "3.0.0+old") }
    sig { returns(Dependabot::Cargo::GraphTransitionPolicy::Package) }
    let(:target) { package("example", "3.0.0+new") }

    it "compares precedence without conflating exact package identities" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Accepted)
      expect(result.reasons.map(&:code)).to include("edge_retargeted")
    end
  end

  context "with a source-changing intent" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Intent]) }
    let(:intents) do
      [
        Dependabot::Cargo::GraphTransitionPolicy::Intent.new(
          previous: old,
          target: package("example", "3.0.0", "git+https://example.com/repo?branch=next#aaaaaaaa")
        )
      ]
    end

    it "does not compare versions across different origins" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
      expect(result.reasons.map(&:code)).to include("identity_changed")
    end
  end

  context "with an invalid target version" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Intent]) }
    let(:intents) do
      [Dependabot::Cargo::GraphTransitionPolicy::Intent.new(previous: old, target: package("example", "invalid"))]
    end

    it "reports invalid input without attempting a version comparison" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
      expect(result.reasons.map(&:code)).to include("invalid_target_version")
    end
  end

  context "with conflicting intents" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Intent]) }
    let(:intents) { super() + [Dependabot::Cargo::GraphTransitionPolicy::Intent.new(previous: old, target: lower)] }

    it "does not arbitrarily choose one" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
      expect(result.reasons.map(&:code)).to include("conflicting_intents")
    end
  end

  context "with a selected parent not in the old graph" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Intent]) }
    let(:intents) do
      [Dependabot::Cargo::GraphTransitionPolicy::Intent.new(
        previous: old,
        target: target,
        parents: [package(
          "missing", "1.0.0", nil
        )]
      )]
    end

    it "reports the invalid selection" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
      expect(result.reasons.map(&:code)).to include("selection_unproven")
    end
  end

  context "when an unselected same-name version changes" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { [edge(parent, target), edge(other_parent, target)] }

    it "does not silently authorize collateral movement" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
      expect(result.reasons.map(&:code)).to include("unselected_edge_changed")
    end
  end

  context "when an old parent already references other versions" do
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:before_edges) { [edge(parent, lower), edge(parent, old), edge(parent, target)] }
    sig { returns(T::Array[Dependabot::Cargo::GraphTransitionPolicy::Edge]) }
    let(:after_edges) { [edge(parent, lower), edge(parent, target)] }

    it "accepts consolidation without requiring a newly added edge" do
      expect(result.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Accepted)
    end
  end

  it "returns helper diagnostics as structured unknown reasons" do
    incomplete = Dependabot::Cargo::LockfileGraph.facts(
      snapshots: {
        "before" => Dependabot::DependencyFile.new(name: "Cargo.lock", content: "version = 99"),
        "after" => lockfile(after_packages, after_edges)
      }
    )
    verdict = described_class.evaluate(facts: incomplete, intents: intents)

    expect(verdict.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
    expect(verdict.reasons.map(&:code)).to include("parse_error")
    expect(T.must(verdict.reasons.first).snapshot).to eq("before")
  end

  it "preserves ambiguous-reference diagnostics without guessing an edge" do
    ambiguous = Dependabot::DependencyFile.new(
      name: "Cargo.lock",
      content: <<~TOML
        version = 3
        [[package]]
        name = "parent"
        version = "1.0.0"
        dependencies = ["example"]
        [[package]]
        name = "example"
        version = "1.0.0"
        [[package]]
        name = "example"
        version = "2.0.0"
      TOML
    )
    incomplete = Dependabot::Cargo::LockfileGraph.facts(snapshots: { "before" => ambiguous, "after" => ambiguous })
    verdict = described_class.evaluate(facts: incomplete, intents: intents)

    expect(verdict.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
    expect(verdict.reasons.map(&:code)).to include("ambiguous_dependency")
    expect(T.must(verdict.reasons.first).diagnostic&.candidates&.size).to eq(2)
  end

  it "rejects an unsupported helper schema without interpreting it" do
    expect(described_class.evaluate(facts: { "schema_version" => 2 }, intents: intents).status)
      .to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
  end

  it "reports malformed helper data explicitly" do
    verdict = described_class.evaluate(facts: { "schema_version" => 1 }, intents: intents)

    expect(verdict.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
    expect(verdict.reasons.map(&:code)).to eq(["malformed_facts"])
  end

  it "rejects malformed snapshot objects explicitly" do
    verdict = described_class.evaluate(facts: { "schema_version" => 1, "snapshots" => [1] }, intents: intents)

    expect(verdict.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
    expect(verdict.reasons.map(&:code)).to eq(["malformed_facts"])
  end

  it "does not authorize an empty update group" do
    verdict = described_class.evaluate(facts: facts, intents: [])

    expect(verdict.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
    expect(verdict.reasons.map(&:code)).to eq(["no_intents"])
  end

  it "requires distinct and uniquely named snapshots" do
    verdict = described_class.evaluate(facts: facts, intents: intents, before: "before", after: "before")

    expect(verdict.status).to eq(Dependabot::Cargo::GraphTransitionPolicy::Status::Unknown)
    expect(verdict.reasons.map(&:code)).to eq(["snapshot_selection"])
  end

  it "adapts a Dependabot dependency only after an exact previous identity is supplied" do
    dependency = Dependabot::Dependency.new(
      name: "example",
      version: "3.0.0",
      previous_version: "2.0.0",
      requirements: [],
      package_manager: "cargo"
    )
    intent = Dependabot::Cargo::GraphTransitionPolicy::Intent.from_dependency(dependency: dependency, previous: old)

    expect(intent.previous.key).to eq(old.key)
    expect(intent.target.key).to eq(target.key)
    expect do
      Dependabot::Cargo::GraphTransitionPolicy::Intent.from_dependency(dependency: dependency, previous: lower)
    end.to raise_error(ArgumentError, /previous identity/)
  end
end

# rubocop:enable RSpec/ScatteredLet
