# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/apm"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Apm::FileParser do
  subject(:parser) do
    described_class.new(dependency_files: files, source: source)
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/agent-repo",
      directory: "/"
    )
  end
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "apm.yml",
      content: fixture("manifests", "apm.yml")
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "apm.lock.yaml",
      content: fixture("manifests", "apm.lock.yaml")
    )
  end
  let(:files) { [manifest, lockfile] }

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    it "only parses the supported string-shorthand git entries pinned to a semver tag" do
      expect(dependencies.map(&:name)).to contain_exactly(
        "microsoft/edge-ai",
        "octo-org/octo-skills",
        "gitlab.com/acme/prompts",
        "qa-org/qa-helpers"
      )
    end

    describe "a GitHub production dependency pinned to a tag" do
      subject(:dependency) { dependencies.find { |d| d.name == "microsoft/edge-ai" } }

      it "has the normalised version and git source" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.version).to eq("1.0.0")
        expect(dependency.production?).to be(true)
        expect(dependency.requirements).to eq(
          [{
            requirement: nil,
            file: "apm.yml",
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/microsoft/edge-ai",
              ref: "v1.0.0",
              branch: nil
            },
            metadata: {
              declaration_string: "microsoft/edge-ai#v1.0.0",
              declaration_span: "4:6:4:30"
            }
          }]
        )
      end
    end

    describe "a dependency hosted on a non-default host" do
      subject(:dependency) { dependencies.find { |d| d.name == "gitlab.com/acme/prompts" } }

      it "keeps the full host in the git URL" do
        expect(dependency.version).to eq("0.5.0")
        expect(dependency.requirements.first[:source][:url])
          .to eq("https://gitlab.com/acme/prompts")
        expect(dependency.requirements.first[:source][:ref]).to eq("v0.5.0")
      end
    end

    describe "a dependency pinned to a branch rather than a semver tag" do
      it "is excluded because it cannot be version-bumped" do
        expect(dependencies.map(&:name)).not_to include("big-corp/pinned-branch")
      end
    end

    context "with two virtual packages in the same repository" do
      let(:manifest) do
        Dependabot::DependencyFile.new(
          name: "apm.yml",
          content: <<~YAML
            dependencies:
              apm:
                - org/mono/skills/review#v1.0.0
                - org/mono/skills/security#v1.0.0
          YAML
        )
      end

      it "keeps them as distinct dependencies namespaced by their virtual path" do
        expect(dependencies.map(&:name)).to contain_exactly(
          "org/mono/skills/review",
          "org/mono/skills/security"
        )
      end
    end

    context "with block scalar entries (folded or literal)" do
      let(:manifest) do
        Dependabot::DependencyFile.new(
          name: "apm.yml",
          content: <<~YAML
            dependencies:
              apm:
                - microsoft/edge-ai#v1.0.0
                - >-
                  octo-org/folded#v1.0.0
                - |-
                  octo-org/literal#v1.0.0
          YAML
        )
      end

      # Block scalars decode to a value that is not a contiguous substring of
      # their raw span, so the updater could not rewrite them. They are skipped
      # at parse time rather than producing a failing update job.
      it "skips them and only parses the flow-scalar entry" do
        expect(dependencies.map(&:name)).to contain_exactly("microsoft/edge-ai")
      end
    end

    context "with a quoted flow-scalar entry" do
      let(:manifest) do
        Dependabot::DependencyFile.new(
          name: "apm.yml",
          content: <<~YAML
            dependencies:
              apm:
                - "octo-org/double-quoted#v1.0.0"
                - 'octo-org/single-quoted#v2.0.0'
          YAML
        )
      end

      it "parses quoted scalars like plain ones" do
        expect(dependencies.map(&:name)).to contain_exactly(
          "octo-org/double-quoted",
          "octo-org/single-quoted"
        )
      end
    end

    context "with an escaped quoted flow-scalar entry" do
      let(:manifest) do
        Dependabot::DependencyFile.new(
          name: "apm.yml",
          # Single-quoted heredoc so the backslash escapes reach YAML verbatim
          # rather than being processed by Ruby first.
          content: <<~'YAML'
            dependencies:
              apm:
                - "octo-org/plain-double#v1.0.0"
                - "octo-org\/escaped\x23v2.0.0"
          YAML
        )
      end

      # The escaped scalar decodes to "octo-org/escaped#v2.0.0", which is not a
      # contiguous substring of its raw span ("octo-org\/escaped\x23v2.0.0"), so
      # the updater could not rewrite it. It is skipped, while the plain double-
      # quoted scalar (which round-trips) is still parsed.
      it "skips it and only parses the round-tripping scalar" do
        expect(dependencies.map(&:name)).to contain_exactly("octo-org/plain-double")
      end
    end

    context "with a quoted entry that has trailing whitespace after the ref" do
      let(:manifest) do
        Dependabot::DependencyFile.new(
          name: "apm.yml",
          content: <<~YAML
            dependencies:
              apm:
                - "octo-org/trailing-space#v1.0.0 "
          YAML
        )
      end

      # The space sits inside the quotes, so the decoded value still round-trips
      # (it is a contiguous slice of the raw span) and the entry is parsed.
      # PackageSpecifier strips the space when reading the ref, while the stored
      # declaration keeps it so the updater can preserve it on rewrite.
      it "parses it, normalises the ref and keeps the raw declaration" do
        expect(dependencies.map(&:name)).to contain_exactly("octo-org/trailing-space")
        expect(dependencies.first.version).to eq("1.0.0")
        expect(dependencies.first.requirements.first[:metadata][:declaration_string])
          .to eq("octo-org/trailing-space#v1.0.0 ")
      end
    end

    context "when a default registry is configured" do
      let(:manifest) do
        Dependabot::DependencyFile.new(
          name: "apm.yml",
          content: <<~YAML
            registries:
              jf-skills:
                url: https://artifactory.example.com/artifactory/api/skills/jf
              default: jf-skills
            dependencies:
              apm:
                - microsoft/edge-ai#v1.0.0
                - gitlab.com/acme/prompts#v0.5.0
                - microsoft/edge-ai-tools.git#v1.0.0
                - git@gitlab.com:acme/ssh-pkg.git#v2.0.0
                - https://gitlab.com/acme/url-pkg.git#v3.0.0
          YAML
        )
      end

      # Bare and FQDN string shorthand route through the registry (out of scope
      # for v1), so only the explicit clone URLs -- including a `.git`-suffixed
      # bare ref, which APM also treats as an explicit git form -- remain as git
      # dependencies.
      it "skips string-shorthand entries and keeps explicit clone URLs" do
        expect(dependencies.map(&:name)).to contain_exactly(
          "microsoft/edge-ai-tools",
          "gitlab.com/acme/ssh-pkg",
          "gitlab.com/acme/url-pkg"
        )
      end
    end

    context "when registries are declared without a default" do
      let(:manifest) do
        Dependabot::DependencyFile.new(
          name: "apm.yml",
          content: <<~YAML
            registries:
              jf-skills:
                url: https://artifactory.example.com/artifactory/api/skills/jf
            dependencies:
              apm:
                - microsoft/edge-ai#v1.0.0
          YAML
        )
      end

      it "still parses string shorthand as git (no routing without a default)" do
        expect(dependencies.map(&:name)).to contain_exactly("microsoft/edge-ai")
      end
    end

    context "with case variations across hosts" do
      let(:manifest) do
        Dependabot::DependencyFile.new(
          name: "apm.yml",
          content: <<~YAML
            dependencies:
              apm:
                - Microsoft/Edge-AI#v1.0.0
                - gitlab.com/Group/Repo#v1.0.0
                - gitlab.com/group/repo#v2.0.0
          YAML
        )
      end

      # GitHub owner/repo casing is canonicalised to lowercase (case-insensitive
      # host); the two GitLab repos differ only by case and MUST stay distinct
      # because GitLab paths are case-sensitive.
      it "case-folds GitHub names but keeps case-sensitive hosts distinct" do
        expect(dependencies.map(&:name)).to contain_exactly(
          "microsoft/edge-ai",
          "gitlab.com/Group/Repo",
          "gitlab.com/group/repo"
        )
      end
    end

    describe "a devDependencies entry" do
      subject(:dependency) { dependencies.find { |d| d.name == "qa-org/qa-helpers" } }

      it "is marked as a development dependency" do
        expect(dependency.version).to eq("3.1.4")
        expect(dependency.requirements.first[:groups]).to eq(["development"])
        expect(dependency.production?).to be(false)
      end
    end

    context "when a package is declared in both dependencies and devDependencies" do
      let(:manifest) do
        Dependabot::DependencyFile.new(
          name: "apm.yml",
          content: <<~YAML
            dependencies:
              apm:
                - microsoft/edge-ai#v1.0.0
            devDependencies:
              apm:
                - microsoft/edge-ai#v1.0.0
          YAML
        )
      end

      # DependencySet merges the two declarations into one dependency, and
      # Dependency#production? flattens every requirement's groups. The explicit
      # production marker must survive that flatten so the dependency stays
      # production rather than being dragged non-production by the dev-only
      # declaration.
      it "keeps the merged dependency in the production group" do
        dependency = dependencies.find { |d| d.name == "microsoft/edge-ai" }
        flattened_groups = dependency.requirements.flat_map { |r| r[:groups] }

        expect(flattened_groups).to include("dependencies", "development")
        expect(dependency.production?).to be(true)
      end
    end

    context "when the manifest has a syntax error" do
      let(:manifest) do
        Dependabot::DependencyFile.new(name: "apm.yml", content: "dependencies: [:")
      end

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "when the manifest has no apm dependency blocks" do
      let(:manifest) do
        Dependabot::DependencyFile.new(name: "apm.yml", content: "default_host: github.com\n")
      end

      it { is_expected.to eq([]) }
    end
  end

  describe "#ecosystem" do
    subject(:ecosystem) { parser.ecosystem }

    it "has the correct name" do
      expect(ecosystem.name).to eq("apm")
    end

    describe "#package_manager" do
      subject(:package_manager) { ecosystem.package_manager }

      it "reads the apm version from the lockfile" do
        expect(package_manager.name).to eq("apm")
        expect(package_manager.version.to_s).to eq("0.4.2")
      end

      context "without a lockfile" do
        let(:files) { [manifest] }

        it "falls back to the default version" do
          expect(package_manager.version.to_s).to eq("0.0.0")
        end
      end

      context "when the lockfile records a PEP 440 apm version" do
        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "apm.lock.yaml",
            content: "apm_version: \"0.32.0rc1\"\ndependencies: []\n"
          )
        end

        it "parses the pre-release CLI version without raising" do
          expect { package_manager.version }.not_to raise_error
          expect(package_manager.version).to be_a(Dependabot::Version)
        end
      end
    end
  end
end
