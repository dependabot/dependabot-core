# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/update_checker/subdependency_version_resolver"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe Dependabot::NpmAndYarn::UpdateChecker::SubdependencyVersionResolver do
  extend T::Sig

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) { project_dependency_files("npm8/multiple_brace_expansion_versions") }

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "brace-expansion",
      version: "2.1.2",
      requirements: [],
      package_manager: "npm_and_yarn"
    )
  end

  sig { returns(Dependabot::NpmAndYarn::UpdateChecker::SubdependencyVersionResolver) }
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: [],
      latest_allowable_version: "5.0.12",
      security_advisories: security_advisories,
      repo_contents_path: nil
    )
  end

  sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
  let(:security_advisories) do
    [
      Dependabot::SecurityAdvisory.new(
        dependency_name: dependency.name,
        package_manager: dependency.package_manager,
        vulnerable_versions: Dependabot::NpmAndYarn::Requirement.requirements_array(">= 2.0.0 < 2.1.4")
      )
    ]
  end

  sig { returns(Dependabot::DependencyFile) }
  let(:lockfile) { T.must(dependency_files.find { |file| file.name == "package-lock.json" }) }

  sig { returns(String) }
  let(:updated_content) { T.must(lockfile.content).gsub('"2.1.2"', '"2.1.4"') }

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_yarn_berry_conflicting_dependencies).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_audit_fix_fallback).and_return(false)
    allow(Dependabot::NpmAndYarn::NativeHelpers).to receive(:run_npm8_subdependency_update_command) do
      File.write("package-lock.json", updated_content)
      ""
    end
  end

  it "reports the version reached by the targeted npm nodes" do
    expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
  end

  context "when the experiment is disabled" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_yarn_berry_conflicting_dependencies).and_return(false)
    end

    it "reports the combined installed version" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("1.1.12"))
    end
  end

  context "with the audit-fix fallback enabled" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_audit_fix_fallback).and_return(true)
    end

    it "does not select an unrelated higher version" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
    end
  end

  context "when the targeted version is unchanged" do
    sig { returns(String) }
    let(:updated_content) { T.must(lockfile.content) }

    it "reports the unchanged target rather than the unrelated lowest version" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.2"))
    end
  end

  context "when the targeted node disappears" do
    sig { returns(String) }
    let(:updated_content) do
      content = JSON.parse(super())
      content.fetch("packages").delete("node_modules/current-parent/node_modules/brace-expansion")
      JSON.generate(content)
    end

    it "does not report an unrelated node as a successful update" do
      allow(Dependabot.logger).to receive(:info)

      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.2"))
      expect(Dependabot.logger).to have_received(:info).with(
        "Cannot verify updated npm resolution for node_modules/current-parent/node_modules/brace-expansion; " \
        "keeping current version"
      )
    end
  end

  context "when the targeted node is hoisted" do
    sig { returns(String) }
    let(:updated_content) do
      content = JSON.parse(super())
      packages = content.fetch("packages")
      packages["node_modules/brace-expansion"] =
        packages.delete("node_modules/current-parent/node_modules/brace-expansion")
      JSON.generate(content)
    end

    it "follows the parent's updated resolution" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
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
        content = JSON.parse(T.must(lockfile.content).gsub('"2.1.2"', '"2.1.4"'))
        packages = content.fetch("packages")
        packages["node_modules/brace-expansion"] =
          packages.delete("node_modules/@scope/current-parent/node_modules/brace-expansion")
        JSON.generate(content)
      end

      it "preserves the scope while following ancestor resolutions" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
      end
    end

    context "with a replacement at an intermediate ancestor" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        files = T.let(super(), T::Array[Dependabot::DependencyFile])
        files.map do |file|
          file.dup.tap do |copy|
            copy.content = T.must(file.content).gsub(
              "node_modules/current-parent", "node_modules/outer/node_modules/current-parent"
            )
          end
        end
      end

      sig { returns(String) }
      let(:updated_content) do
        content = JSON.parse(T.must(lockfile.content).gsub('"2.1.2"', '"2.1.4"'))
        packages = content.fetch("packages")
        packages["node_modules/outer/node_modules/brace-expansion"] =
          packages.delete("node_modules/outer/node_modules/current-parent/node_modules/brace-expansion")
        packages["node_modules/brace-expansion"] = { "version" => "5.0.12" }
        JSON.generate(content)
      end

      it "prefers the closest replacement over an unrelated root version" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
      end
    end
  end

  context "when consumers of a hoisted target resolve different versions after updating" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      files.map do |file|
        next file unless file.name == "package-lock.json"

        content = JSON.parse(T.must(file.content))
        packages = content.fetch("packages")
        packages["node_modules/brace-expansion"] =
          packages.delete("node_modules/current-parent/node_modules/brace-expansion")
        packages["node_modules/another-parent"] = {
          "version" => "1.0.0", "dependencies" => { "brace-expansion" => "^2.0.2" }
        }
        file.dup.tap { |copy| copy.content = JSON.generate(content) }
      end
    end

    sig { returns(String) }
    let(:updated_content) do
      content = JSON.parse(super())
      content.fetch("packages")["node_modules/another-parent/node_modules/brace-expansion"] = { "version" => "2.1.2" }
      JSON.generate(content)
    end

    it "checks every original incoming dependency edge" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.2"))
    end
  end

  context "when one of several targeted nodes remains vulnerable" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      files.map do |file|
        next file unless file.name == "package-lock.json"

        content = JSON.parse(T.must(file.content))
        content.fetch("packages")["node_modules/another-parent/node_modules/brace-expansion"] = { "version" => "2.1.2" }
        file.dup.tap { |copy| copy.content = JSON.generate(content) }
      end
    end

    sig { returns(String) }
    let(:updated_content) { T.must(lockfile.content).sub('"2.1.2"', '"2.1.4"') }

    it "does not report the partial update as fixing the targeted version" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.2"))
    end
  end

  context "when a higher targeted result remains vulnerable" do
    sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
    let(:security_advisories) do
      advisories = T.let(super(), T::Array[Dependabot::SecurityAdvisory])
      advisories + [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency.name,
          package_manager: dependency.package_manager,
          vulnerable_versions: Dependabot::NpmAndYarn::Requirement.requirements_array(">= 3.0.0 < 4.0.0")
        )
      ]
    end

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      files.map do |file|
        next file unless file.name == "package-lock.json"

        content = JSON.parse(T.must(file.content))
        packages = content.fetch("packages")
        packages["node_modules/another-parent"] = {
          "version" => "1.0.0", "dependencies" => { "brace-expansion" => "^2.0.2 || ^3.0.0" }
        }
        packages["node_modules/another-parent/node_modules/brace-expansion"] = { "version" => "2.1.2" }
        file.dup.tap { |copy| copy.content = JSON.generate(content) }
      end
    end

    sig { returns(String) }
    let(:updated_content) do
      content = JSON.parse(super())
      content.fetch("packages").fetch("node_modules/another-parent/node_modules/brace-expansion")["version"] = "3.0.0"
      JSON.generate(content)
    end

    it "does not accept a safe minimum as a complete security fix" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.2"))
    end

    it "retains each originally targeted resolution in the lockfile reader" do
      updated = lockfile.dup
      updated.content = updated_content

      versions = Dependabot::NpmAndYarn::FileParser::JsonLock.new(updated)
                                                             .updated_dependency_versions(
                                                               dependency: dependency, original: lockfile
                                                             )

      expect(versions).to contain_exactly(
        Dependabot::NpmAndYarn::Version.new("2.1.4"), Dependabot::NpmAndYarn::Version.new("3.0.0")
      )
    end

    it "rejects the partial fix through the public update checker despite a safe latest release" do
      versions = %w(1.1.12 2.1.2 2.1.4 3.0.0 5.0.2 5.0.12)
      response = {
        "name" => dependency.name,
        "dist-tags" => { "latest" => "5.0.12" },
        "versions" => versions.to_h { |version| [version, { "name" => dependency.name, "version" => version }] }
      }
      stub_request(:get, "https://registry.npmjs.org/brace-expansion")
        .to_return(status: 200, body: response.to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:head, %r{\Ahttps://registry\.npmjs\.org/brace-expansion/-/brace-expansion-[\d.]+\.tgz\z})
        .to_return(status: 200)
      checker = Dependabot::NpmAndYarn::UpdateChecker.new(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: [],
        security_advisories: security_advisories
      )
      allow(checker).to receive(:conflicting_dependencies).and_return([])

      expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
    end

    context "when all targeted results are safe" do
      sig { returns(String) }
      let(:updated_content) { super().gsub('"3.0.0"', '"3.0.1"') }

      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency.name,
            package_manager: dependency.package_manager,
            vulnerable_versions: Dependabot::NpmAndYarn::Requirement.requirements_array(
              ">= 2.0.0 < 2.1.4 || = 3.0.0"
            )
          )
        ]
      end

      it "accepts different safe resulting versions" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
      end
    end

    context "when the vulnerable result is in a different lockfile" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        files = T.let(super(), T::Array[Dependabot::DependencyFile])
        files + files.map do |file|
          Dependabot::DependencyFile.new(name: "nested/#{file.name}", content: file.content)
        end
      end

      sig { returns(String) }
      let(:updated_content) { T.must(lockfile.content).gsub('"2.1.2"', '"2.1.4"') }

      before do
        allow(Dependabot::NpmAndYarn::NativeHelpers).to receive(:run_npm8_subdependency_update_command) do
          content = Dir.pwd.end_with?("/nested") ? updated_content.gsub('"2.1.4"', '"3.0.0"') : updated_content
          File.write("package-lock.json", content)
          ""
        end
      end

      it "checks all targeted results across lockfiles before reducing them to one version" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.2"))
        expect(Dependabot::NpmAndYarn::NativeHelpers)
          .to have_received(:run_npm8_subdependency_update_command).twice
      end
    end
  end

  context "with a shrinkwrap" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      files.map do |file|
        next file unless file.name == "package-lock.json"

        Dependabot::DependencyFile.new(name: "npm-shrinkwrap.json", content: file.content)
      end
    end

    sig { returns(Dependabot::DependencyFile) }
    let(:lockfile) { T.must(dependency_files.find { |file| file.name == "npm-shrinkwrap.json" }) }

    before do
      allow(Dependabot::NpmAndYarn::NativeHelpers).to receive(:run_npm8_subdependency_update_command) do
        File.write("npm-shrinkwrap.json", updated_content)
        ""
      end
    end

    it "tracks the targeted shrinkwrap node" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
    end

    context "with a shadowed package lock in the same directory" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        files = T.let(super(), T::Array[Dependabot::DependencyFile])
        shrinkwrap = T.must(files.find { |file| file.name == "npm-shrinkwrap.json" })
        files + [Dependabot::DependencyFile.new(name: "package-lock.json", content: shrinkwrap.content)]
      end

      it "ignores the unchanged package lock when verifying the security fix" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
        expect(Dependabot::NpmAndYarn::NativeHelpers)
          .to have_received(:run_npm8_subdependency_update_command).once
      end

      context "when the experiment is disabled" do
        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:enable_yarn_berry_conflicting_dependencies).and_return(false)
        end

        it "retains the original lockfile selection and combined version" do
          expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("1.1.12"))
          expect(Dependabot::NpmAndYarn::NativeHelpers)
            .to have_received(:run_npm8_subdependency_update_command).twice
        end
      end

      context "with lockfiles in a subdirectory" do
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        let(:dependency_files) do
          files = T.let(super(), T::Array[Dependabot::DependencyFile])
          files.map do |file|
            Dependabot::DependencyFile.new(name: "nested/#{file.name}", content: file.content)
          end + [Dependabot::DependencyFile.new(name: "package.json", content: '{"private":true}')]
        end

        sig { returns(Dependabot::DependencyFile) }
        let(:lockfile) { T.must(dependency_files.find { |file| file.name == "nested/npm-shrinkwrap.json" }) }

        it "applies shrinkwrap precedence within the lockfile directory" do
          expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
          expect(Dependabot::NpmAndYarn::NativeHelpers)
            .to have_received(:run_npm8_subdependency_update_command).once
        end
      end
    end
  end

  context "with an npm 6 lockfile" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) { project_dependency_files("npm6/multiple_brace_expansion_versions") }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
        .with(
          command: Dependabot::NpmAndYarn::NativeHelpers.helper_path,
          function: "npm6:updateSubdependency",
          args: [anything, "package-lock.json", [dependency.to_h]]
        ).and_return({ "package-lock.json" => updated_content })
    end

    it "tracks the original nested dependency path" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
    end

    context "when the targeted legacy node is hoisted" do
      sig { returns(String) }
      let(:updated_content) do
        content = JSON.parse(super())
        dependencies = content.fetch("dependencies")
        dependencies["brace-expansion"] =
          dependencies.fetch("current-parent").fetch("dependencies").delete("brace-expansion")
        JSON.generate(content)
      end

      it "follows the legacy requires edge to its replacement" do
        expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
      end
    end
  end

  context "with an npm 7 lockfile containing legacy and modern tables" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      legacy = project_dependency_files("npm6/multiple_brace_expansion_versions")
      legacy_lock = T.must(legacy.find { |file| file.name == "package-lock.json" })
      legacy_dependencies = JSON.parse(T.must(legacy_lock.content)).fetch("dependencies")
      files.map do |file|
        next file unless file.name == "package-lock.json"

        content = JSON.parse(T.must(file.content)).merge(
          "lockfileVersion" => 2, "dependencies" => legacy_dependencies
        )
        file.dup.tap { |copy| copy.content = JSON.generate(content) }
      end
    end

    it "tracks the installed package table rather than an unrelated resolution" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
    end
  end
end
