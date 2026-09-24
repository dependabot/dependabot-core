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
        expect(spec.name).to eq("git.internal.example/team/skills")
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

    context "with a non-string entry" do
      let(:raw) { { "git" => "https://github.com/example/object-form" } }

      it { is_expected.to be_nil }
    end
  end
end
