# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/update_checker/subdependency_version_resolver"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe Dependabot::Bun::UpdateChecker::SubdependencyVersionResolver do
  extend T::Sig

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) { project_dependency_files("bun/multiple_brace_expansion_versions") }

  sig { returns(Dependabot::DependencyFile) }
  let(:lockfile) { T.must(dependency_files.find { |file| file.name == "bun.lock" }) }

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "brace-expansion", version: "2.1.2", requirements: [], package_manager: "bun"
    )
  end

  sig { returns(T.any(String, Dependabot::Bun::Version)) }
  let(:latest_allowable_version) { "5.0.12" }

  sig { returns(Dependabot::Bun::UpdateChecker::SubdependencyVersionResolver) }
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: [],
      latest_allowable_version: latest_allowable_version,
      repo_contents_path: nil
    )
  end

  sig { returns(String) }
  let(:updated_content) { T.must(lockfile.content).gsub("brace-expansion@2.1.2", "brace-expansion@2.1.4") }

  before do
    allow(Dependabot::Bun::Helpers).to receive(:run_bun_command) do
      File.write("bun.lock", updated_content)
      ""
    end
  end

  it "reports the updated target instead of an unrelated lower version" do
    expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.4"))
  end

  context "with mixed Git and registry dependencies" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) { project_dependency_files("bun/github_dependency_no_ref") }

    sig { returns(String) }
    let(:latest_allowable_version) { "6.20.1" }

    sig { returns(Dependabot::Dependency) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "undici-types", version: "6.20.0", requirements: [], package_manager: "bun"
      )
    end

    sig { returns(String) }
    let(:updated_content) { T.must(lockfile.content).gsub("undici-types@6.20.0", "undici-types@6.20.1") }

    before do
      fetcher = instance_double(Dependabot::GitMetadataFetcher, tags: [])
      allow(Dependabot::GitMetadataFetcher).to receive(:new).and_return(fetcher)
    end

    it "resolves a registry update without rejecting the Git tuple" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("6.20.1"))
    end
  end

  context "when the targeted version is unchanged" do
    sig { returns(String) }
    let(:updated_content) { T.must(lockfile.content) }

    it "reports the unchanged targeted version" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.2"))
    end
  end

  context "when the targeted entry disappears" do
    sig { returns(String) }
    let(:updated_content) do
      content = JSON.parse(super())
      content.fetch("packages").delete("current-parent/brace-expansion")
      JSON.generate(content)
    end

    it "does not report an unrelated entry as the result" do
      allow(Dependabot.logger).to receive(:info)

      expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.2"))
      expect(Dependabot.logger).to have_received(:info).with(
        "Cannot verify updated Bun resolution for current-parent/brace-expansion; keeping current version"
      )
    end
  end

  context "when the targeted entry is hoisted" do
    sig { returns(String) }
    let(:updated_content) do
      content = JSON.parse(super())
      packages = content.fetch("packages")
      packages["brace-expansion"] = packages.delete("current-parent/brace-expansion")
      JSON.generate(content)
    end

    it "follows the parent's updated resolution" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.4"))
    end

    context "with a scoped parent" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        files = T.let(super(), T::Array[Dependabot::DependencyFile])
        files.map do |file|
          file.dup.tap { |copy| copy.content = T.must(file.content).gsub("current-parent", "@scope/current-parent") }
        end
      end

      sig { returns(String) }
      let(:updated_content) do
        content = JSON.parse(T.must(lockfile.content).gsub("brace-expansion@2.1.2", "brace-expansion@2.1.4"))
        packages = content.fetch("packages")
        packages["brace-expansion"] = packages.delete("@scope/current-parent/brace-expansion")
        JSON.generate(content)
      end

      it "preserves the scope while following ancestor resolutions" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.4"))
      end
    end

    context "with a replacement at an intermediate ancestor" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        files = T.let(super(), T::Array[Dependabot::DependencyFile])
        files.map do |file|
          file.dup.tap do |copy|
            copy.content = T.must(file.content).gsub('"current-parent', '"outer/current-parent')
          end
        end
      end

      sig { returns(String) }
      let(:updated_content) do
        content = JSON.parse(T.must(lockfile.content).gsub("brace-expansion@2.1.2", "brace-expansion@2.1.4"))
        packages = content.fetch("packages")
        packages["outer/brace-expansion"] = packages.delete("outer/current-parent/brace-expansion")
        packages["brace-expansion"] = ["brace-expansion@5.0.12", "", {}, ""]
        JSON.generate(content)
      end

      it "prefers the closest replacement over an unrelated root version" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.4"))
      end
    end
  end

  context "when consumers of a hoisted target resolve different versions after updating" do
    sig { returns(String) }
    let(:edge_type) { "dependencies" }

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      files.map do |file|
        next file unless file.name == "bun.lock"

        content = JSON.parse(T.must(file.content))
        packages = content.fetch("packages")
        packages["brace-expansion"] = packages.delete("current-parent/brace-expansion")
        packages["another-parent"] =
          ["another-parent@1.0.0", "", { edge_type => { "brace-expansion" => "^2.0.2" } }, ""]
        file.dup.tap { |copy| copy.content = JSON.generate(content) }
      end
    end

    sig { returns(String) }
    let(:updated_content) do
      content = JSON.parse(super())
      content.fetch("packages")["another-parent/brace-expansion"] = ["brace-expansion@2.1.2", "", {}, ""]
      JSON.generate(content)
    end

    it "checks every original incoming dependency edge" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.2"))
    end

    context "with a Git consumer" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        files = T.let(super(), T::Array[Dependabot::DependencyFile])
        files.map do |file|
          next file unless file.name == "bun.lock"

          content = JSON.parse(T.must(file.content))
          packages = content.fetch("packages")
          metadata = packages.fetch("another-parent")[2]
          packages["another-parent"] = ["another-parent@github:example/parent#123abcd", metadata, "parent-123abcd"]
          file.dup.tap { |copy| copy.content = JSON.generate(content) }
        end
      end

      it "follows dependency edges from Git metadata rather than skipping the package" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.2"))
      end
    end

    context "with an optional consumer" do
      sig { returns(String) }
      let(:edge_type) { "optionalDependencies" }

      it "does not report success while the optional consumer remains vulnerable" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.2"))
      end
    end

    context "with a peer consumer" do
      sig { returns(String) }
      let(:edge_type) { "peerDependencies" }

      it "does not report success while the peer consumer remains vulnerable" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.2"))
      end
    end
  end

  context "with an aliased transitive dependency" do
    sig { returns(String) }
    let(:installation_name) { "my-brace" }

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      files.map do |file|
        next file unless file.name == "bun.lock"

        content = JSON.parse(T.must(file.content))
        packages = content.fetch("packages")
        packages["current-parent"][2]["dependencies"] = {
          installation_name => "npm:brace-expansion@^2.0.2"
        }
        packages["current-parent/#{installation_name}"] = packages.delete("current-parent/brace-expansion")
        file.dup.tap { |copy| copy.content = JSON.generate(content) }
      end
    end

    it "verifies the updated alias using its installed name" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.4"))
    end

    context "when the alias is hoisted" do
      sig { returns(String) }
      let(:updated_content) do
        content = JSON.parse(super())
        packages = content.fetch("packages")
        packages[installation_name] = packages.delete("current-parent/#{installation_name}")
        JSON.generate(content)
      end

      it "follows the aliased incoming dependency edge" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.4"))
      end

      context "with a scoped alias" do
        sig { returns(String) }
        let(:installation_name) { "@scope/my-brace" }

        it "keeps the scope in the lookup name" do
          expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.4"))
        end
      end
    end

    context "when the alias now names a different package" do
      sig { returns(String) }
      let(:updated_content) { super().gsub("brace-expansion@2.1.4", "other-package@2.1.4") }

      it "does not verify an update to the wrong real package" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::Bun::Version.new("2.1.2"))
      end
    end
  end
end
