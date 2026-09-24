# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/apm/package_specifier"

RSpec.describe Dependabot::Apm::PackageSpecifier do
  describe ".parse" do
    subject(:spec) { described_class.parse(raw, default_host: default_host) }

    let(:default_host) { "github.com" }

    context "with a GitHub shorthand and no ref" do
      let(:raw) { "microsoft/edge-ai" }

      it "parses the owner and repo against the default host" do
        expect(spec.host).to eq("github.com")
        expect(spec.owner).to eq("microsoft")
        expect(spec.repo).to eq("edge-ai")
        expect(spec.sub_path).to be_nil
        expect(spec.ref).to be_nil
        expect(spec.git_url).to eq("https://github.com/microsoft/edge-ai")
        expect(spec.name).to eq("microsoft/edge-ai")
      end
    end

    context "with a GitHub shorthand pinned to a tag" do
      let(:raw) { "microsoft/edge-ai#v1.0.0" }

      it "captures the ref" do
        expect(spec.owner).to eq("microsoft")
        expect(spec.repo).to eq("edge-ai")
        expect(spec.ref).to eq("v1.0.0")
      end
    end

    context "with a virtual subdirectory" do
      let(:raw) { "octo-org/octo-skills/skills/review#v2.3.1" }

      it "keeps the repo and records the sub path" do
        expect(spec.owner).to eq("octo-org")
        expect(spec.repo).to eq("octo-skills")
        expect(spec.sub_path).to eq("skills/review")
        expect(spec.ref).to eq("v2.3.1")
        expect(spec.git_url).to eq("https://github.com/octo-org/octo-skills")
      end

      it "namespaces the dependency name by the virtual path so it stays unique" do
        expect(spec.name).to eq("octo-org/octo-skills/skills/review")
      end
    end

    context "with an FQDN shorthand for a non-default host" do
      let(:raw) { "gitlab.com/acme/prompts#v0.5.0" }

      it "uses the host from the entry" do
        expect(spec.host).to eq("gitlab.com")
        expect(spec.owner).to eq("acme")
        expect(spec.repo).to eq("prompts")
        expect(spec.ref).to eq("v0.5.0")
        expect(spec.git_url).to eq("https://gitlab.com/acme/prompts")
      end

      it "namespaces the dependency name by host" do
        expect(spec.name).to eq("gitlab.com/acme/prompts")
      end
    end

    context "with a nested subgroup repository on a non-default host" do
      let(:raw) { "gitlab.com/group/subgroup/project#v1.2.0" }

      it "keeps the full nested path as the repository rather than a virtual path" do
        expect(spec.host).to eq("gitlab.com")
        expect(spec.owner).to eq("group")
        expect(spec.repo).to eq("subgroup/project")
        expect(spec.sub_path).to be_nil
        expect(spec.ref).to eq("v1.2.0")
        expect(spec.git_url).to eq("https://gitlab.com/group/subgroup/project")
        expect(spec.name).to eq("gitlab.com/group/subgroup/project")
      end
    end

    context "with an explicit URL whose host is mixed case" do
      let(:raw) { "https://GitHub.com/org/repo/skills/review#v1.0.0" }

      it "canonicalises the host to lowercase and treats it as a GitHub virtual package" do
        expect(spec.host).to eq("github.com")
        expect(spec.owner).to eq("org")
        expect(spec.repo).to eq("repo")
        expect(spec.sub_path).to eq("skills/review")
        expect(spec.ref).to eq("v1.0.0")
        expect(spec.git_url).to eq("https://github.com/org/repo")
        expect(spec.name).to eq("org/repo/skills/review")
      end
    end

    context "with a virtual sub-path on a GitHub Enterprise Cloud host" do
      let(:raw) { "acme.ghe.com/org/repo/skills/review#v1.0.0" }

      it "treats *.ghe.com as GitHub and splits owner/repo from the virtual path" do
        expect(spec.host).to eq("acme.ghe.com")
        expect(spec.owner).to eq("org")
        expect(spec.repo).to eq("repo")
        expect(spec.sub_path).to eq("skills/review")
        expect(spec.ref).to eq("v1.0.0")
        expect(spec.git_url).to eq("https://acme.ghe.com/org/repo")
      end

      it "namespaces the dependency name by the qualified host and virtual path" do
        expect(spec.name).to eq("acme.ghe.com/org/repo/skills/review")
      end
    end

    context "with a mixed-case owner and repo on a GitHub Enterprise Cloud host" do
      let(:raw) { "acme.ghe.com/Org/Repo#v1.0.0" }

      it "canonicalises owner and repo to lowercase like github.com" do
        expect(spec.host).to eq("acme.ghe.com")
        expect(spec.owner).to eq("org")
        expect(spec.repo).to eq("repo")
        expect(spec.sub_path).to be_nil
        expect(spec.git_url).to eq("https://acme.ghe.com/org/repo")
        expect(spec.name).to eq("acme.ghe.com/org/repo")
      end
    end

    context "with a host that merely ends in ghe.com but is not a subdomain" do
      let(:raw) { "notghe.com/group/subgroup/project#v1.2.0" }

      it "does not treat it as GitHub and keeps the full nested path as the repo" do
        expect(spec.host).to eq("notghe.com")
        expect(spec.owner).to eq("group")
        expect(spec.repo).to eq("subgroup/project")
        expect(spec.sub_path).to be_nil
        expect(spec.git_url).to eq("https://notghe.com/group/subgroup/project")
      end
    end

    context "with an explicit HTTPS git URL" do
      let(:raw) { "https://gitlab.com/acme/prompts.git#v0.5.0" }

      it "parses host, owner and repo and drops the .git suffix" do
        expect(spec.host).to eq("gitlab.com")
        expect(spec.owner).to eq("acme")
        expect(spec.repo).to eq("prompts")
        expect(spec.ref).to eq("v0.5.0")
      end
    end

    context "with an SSH SCP-style URL" do
      let(:raw) { "git@gitlab.com:acme/prompts.git#v0.5.0" }

      it "parses host, owner and repo" do
        expect(spec.host).to eq("gitlab.com")
        expect(spec.owner).to eq("acme")
        expect(spec.repo).to eq("prompts")
        expect(spec.ref).to eq("v0.5.0")
      end
    end

    context "with an SSH SCP-style URL using a non-default user" do
      let(:raw) { "myuser@gitlab.com:acme/prompts.git#v0.5.0" }

      it "accepts any SSH user and parses host, owner and repo" do
        expect(spec.host).to eq("gitlab.com")
        expect(spec.owner).to eq("acme")
        expect(spec.repo).to eq("prompts")
        expect(spec.ref).to eq("v0.5.0")
        expect(spec.git_url).to eq("https://gitlab.com/acme/prompts")
      end
    end

    context "with an SSH URI-style URL" do
      let(:raw) { "ssh://git@gitlab.com/acme/prompts.git#v0.5.0" }

      it "strips the user info and parses host, owner and repo" do
        expect(spec.host).to eq("gitlab.com")
        expect(spec.owner).to eq("acme")
        expect(spec.repo).to eq("prompts")
        expect(spec.ref).to eq("v0.5.0")
        expect(spec.git_url).to eq("https://gitlab.com/acme/prompts")
      end
    end

    context "when the default host is overridden" do
      let(:default_host) { "git.internal.example" }
      let(:raw) { "team/skills#v1.0.0" }

      it "resolves the shorthand against the provided default host" do
        expect(spec.host).to eq("git.internal.example")
        expect(spec.git_url).to eq("https://git.internal.example/team/skills")
      end

      it "strips the configured default host from the dependency name" do
        # The manifest-selected default host is APM's implicit host, so the
        # canonical identity omits it -- keeping dependency-name ignore rules
        # and deduplication aligned with the identity APM itself uses.
        expect(spec.name).to eq("team/skills")
      end

      context "when the entry explicitly repeats that default host" do
        let(:raw) { "git.internal.example/team/skills#v1.0.0" }

        it "still strips it, so both spellings share one identity" do
          expect(spec.name).to eq("team/skills")
        end
      end

      context "when the entry explicitly names a different host" do
        let(:raw) { "github.com/team/skills#v1.0.0" }

        it "qualifies the non-default host in the name" do
          expect(spec.host).to eq("github.com")
          expect(spec.name).to eq("github.com/team/skills")
        end
      end
    end

    context "with local path entries" do
      [
        "./local-pkg", "../local-pkg", "/abs/local-pkg", ".",
        "~/local-pkg", "~", ".\\local-pkg", "..\\local-pkg", "~\\local-pkg"
      ].each do |path|
        context "with #{path}" do
          let(:raw) { path }

          it { is_expected.to be_nil }
        end
      end
    end

    context "with an empty or blank entry" do
      let(:raw) { "   " }

      it { is_expected.to be_nil }
    end

    context "with an entry that has no repo segment" do
      let(:raw) { "just-an-owner" }

      it { is_expected.to be_nil }
    end

    context "with a mixed-case GitHub shorthand" do
      let(:raw) { "Microsoft/Edge-AI#v1.0.0" }

      it "canonicalises owner and repo to lowercase" do
        expect(spec.owner).to eq("microsoft")
        expect(spec.repo).to eq("edge-ai")
        expect(spec.name).to eq("microsoft/edge-ai")
        expect(spec.git_url).to eq("https://github.com/microsoft/edge-ai")
      end
    end

    context "with a mixed-case shorthand on a case-sensitive host" do
      let(:raw) { "gitlab.com/Group/Repo#v1.0.0" }

      it "preserves repository-path casing" do
        expect(spec.host).to eq("gitlab.com")
        expect(spec.owner).to eq("Group")
        expect(spec.repo).to eq("Repo")
        expect(spec.name).to eq("gitlab.com/Group/Repo")
      end
    end

    context "with a mixed-case GitHub virtual package" do
      let(:raw) { "Octo-Org/Octo-Skills/Skills/Review#v1.0.0" }

      it "case-folds owner and repo but preserves the virtual sub path" do
        expect(spec.owner).to eq("octo-org")
        expect(spec.repo).to eq("octo-skills")
        expect(spec.sub_path).to eq("Skills/Review")
        expect(spec.name).to eq("octo-org/octo-skills/Skills/Review")
      end
    end

    context "with a non-string entry" do
      let(:raw) { { "git" => "https://github.com/example/object-form" } }

      it { is_expected.to be_nil }
    end
  end

  describe ".shorthand?" do
    it "is true for bare and host-qualified string shorthand" do
      expect(described_class.shorthand?("owner/repo")).to be(true)
      expect(described_class.shorthand?("owner/repo#v1.2.3")).to be(true)
      expect(described_class.shorthand?("gitlab.com/acme/repo#v2.0.0")).to be(true)
    end

    it "is false for explicit clone URLs (never registry-routed)" do
      expect(described_class.shorthand?("https://gitlab.com/acme/repo.git#v1.0.0")).to be(false)
      expect(described_class.shorthand?("http://gitlab.com/acme/repo.git")).to be(false)
      expect(described_class.shorthand?("ssh://git@gitlab.com/acme/repo.git#v1.0.0")).to be(false)
      expect(described_class.shorthand?("git@gitlab.com:acme/repo.git#v1.0.0")).to be(false)
      expect(described_class.shorthand?("myuser@gitlab.com:acme/repo.git")).to be(false)
    end

    it "is false for local paths and non-strings" do
      expect(described_class.shorthand?("./local")).to be(false)
      expect(described_class.shorthand?("   ")).to be(false)
      expect(described_class.shorthand?({ "git" => "x" })).to be(false)
    end
  end
end
