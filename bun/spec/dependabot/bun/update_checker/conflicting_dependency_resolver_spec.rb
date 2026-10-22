# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/update_checker/conflicting_dependency_resolver"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe Dependabot::Bun::UpdateChecker::ConflictingDependencyResolver do
  extend T::Sig

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "brace-expansion", version: "2.1.2", requirements: [], package_manager: "bun"
    )
  end

  sig { returns(Dependabot::Bun::UpdateChecker::ConflictingDependencyResolver) }
  let(:resolver) do
    described_class.new(
      dependency_files: dependency_files, credentials: []
    )
  end

  sig { returns(String) }
  let(:target_requirement) { "^2.0.2" }

  sig { returns(T::Hash[String, Object]) }
  let(:parent_metadata) { { "dependencies" => { "brace-expansion" => target_requirement } } }

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) do
    project_dependency_files("bun/multiple_brace_expansion_versions").map do |file|
      next file unless file.name == "bun.lock"

      content = JSON.parse(T.must(file.content))
      content.fetch("packages").fetch("current-parent")[2] = parent_metadata
      file.dup.tap { |copy| copy.content = JSON.generate(content) }
    end
  end

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_yarn_berry_conflicting_dependencies).and_return(true)
  end

  it "ignores incompatible requirements resolving to other installed versions" do
    expect(resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")).to be_empty
  end

  context "when the targeted installed copy is pinned" do
    sig { returns(String) }
    let(:target_requirement) { "2.1.2" }

    it "reports the parent blocking the security fix from the Bun lockfile" do
      expect(resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")).to eq(
        [{
          "name" => "current-parent",
          "version" => "1.0.0",
          "requirement" => "2.1.2",
          "explanation" => "current-parent@1.0.0 requires brace-expansion@2.1.2"
        }]
      )
    end

    context "with optional and peer dependency edges" do
      sig { returns(T::Hash[String, Object]) }
      let(:parent_metadata) do
        {
          "optionalDependencies" => { "brace-expansion" => "2.1.2" },
          "peerDependencies" => { "brace-expansion" => "^2.0.2" }
        }
      end

      it "retains the incompatible edge even when another edge accepts the fix" do
        conflicts = resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")

        expect(conflicts).to contain_exactly(hash_including("name" => "current-parent", "requirement" => "2.1.2"))
      end
    end

    context "with a scoped alias and hoisted resolution" do
      sig { returns(T::Hash[String, Object]) }
      let(:parent_metadata) { { "dependencies" => { "@scope/alias" => "npm:brace-expansion@#{target_requirement}" } } }

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        T.let(super(), T::Array[Dependabot::DependencyFile]).map do |file|
          next file unless file.name == "bun.lock"

          content = JSON.parse(T.must(file.content))
          packages = content.fetch("packages")
          packages["@scope/alias"] = packages.delete("current-parent/brace-expansion")
          file.dup.tap { |copy| copy.content = JSON.generate(content) }
        end
      end

      it "matches the real package identity while resolving the alias installation path" do
        conflicts = resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")

        expect(conflicts).to contain_exactly(
          hash_including("name" => "current-parent", "requirement" => "npm:brace-expansion@2.1.2")
        )
      end

      context "when the alias range permits the fix" do
        sig { returns(String) }
        let(:target_requirement) { "^2.0.2" }

        it "does not report the alias protocol as an incompatible requirement" do
          expect(resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")).to be_empty
        end
      end
    end

    context "with a non-registry parent" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        T.let(super(), T::Array[Dependabot::DependencyFile]).map do |file|
          next file unless file.name == "bun.lock"

          content = JSON.parse(T.must(file.content))
          content.fetch("packages")["current-parent"] = ["current-parent@file:../parent", parent_metadata]
          file.dup.tap { |copy| copy.content = JSON.generate(content) }
        end
      end

      it "reads the dependency metadata without a registry field" do
        conflicts = resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")

        expect(conflicts).to contain_exactly(
          hash_including("name" => "current-parent", "version" => "file:../parent", "requirement" => "2.1.2")
        )
      end
    end
  end

  context "with another Bun lockfile" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      lockfile = T.must(files.find { |file| file.name == "bun.lock" })
      content = JSON.parse(T.must(lockfile.content))
      content.fetch("packages").fetch("current-parent")[2] = { "dependencies" => { "brace-expansion" => "2.1.2" } }
      files + [Dependabot::DependencyFile.new(name: "packages/member/bun.lock", content: JSON.generate(content))]
    end

    it "does not miss blockers outside the root lockfile" do
      conflicts = resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")

      expect(conflicts).to contain_exactly(hash_including("name" => "current-parent", "requirement" => "2.1.2"))
    end
  end

  context "with a non-string requirement" do
    sig { returns(T::Hash[String, Object]) }
    let(:parent_metadata) { { "dependencies" => { "brace-expansion" => 123 } } }

    it "surfaces the invalid dependency edge" do
      expect do
        resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")
      end.to raise_error(Dependabot::DependencyFileNotParseable, /must be a string/)
    end
  end

  context "with a dist-tag requirement" do
    sig { returns(String) }
    let(:target_requirement) { "latest" }

    it "conservatively retains a requirement that cannot be verified against the fix" do
      conflicts = resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")

      expect(conflicts).to contain_exactly(hash_including("name" => "current-parent", "requirement" => "latest"))
    end
  end

  context "with an invalid Bun lockfile" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) { [Dependabot::DependencyFile.new(name: "bun.lock", content: "{invalid")] }

    it "surfaces the parse error instead of reporting no conflicts" do
      expect do
        resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")
      end.to raise_error(Dependabot::DependencyFileNotParseable)
    end
  end

  context "when the experiment is disabled" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_yarn_berry_conflicting_dependencies).and_return(false)
      allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_return([])
    end

    it "passes the original unscoped arguments to the conflict helper" do
      expect(resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")).to be_empty
      expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess)
        .with(
          command: Dependabot::Bun::NativeHelpers.helper_path,
          function: "yarn:findConflictingDependencies",
          args: [a_kind_of(String), "brace-expansion", "2.1.4"]
        )
    end
  end
end
