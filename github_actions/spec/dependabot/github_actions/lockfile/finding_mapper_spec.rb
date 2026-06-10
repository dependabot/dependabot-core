# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions/lockfile"

# Covers the gh-actions-pin finding category -> Dependabot error mapping AT THE
# RELOCK GATE. This runs after a `check` fix-mode pass, so the findings array is a
# PRE-fix diagnosis: ref-changed/stale/etc. are already re-pinned/pruned on disk
# and must NOT block. The ONLY categories fix-mode cannot resolve — impostor-commit
# and lockfile-forgery — map to UnresolvableDependency; everything else returns nil.
# Blocking is still gated on the `severity` field.
RSpec.describe Dependabot::GithubActions::Lockfile::FindingMapper do
  subject(:error) { described_class.error_for(finding) }

  describe ".error_for" do
    context "with an impostor-commit finding" do
      let(:finding) do
        { "category" => "impostor-commit", "severity" => "error",
          "dependency" => "actions/setup-node@v4", "detail" => "SHA not reachable from any branch" }
      end

      it "maps to UnresolvableDependency" do
        expect(error).to be_a(Dependabot::GithubActions::Lockfile::UnresolvableDependency)
        expect(error.message).to include("actions/setup-node@v4")
        expect(error.message).to include("SHA not reachable from any branch")
      end
    end

    context "with a lockfile-forgery finding" do
      let(:finding) do
        { "category" => "lockfile-forgery", "severity" => "error",
          "dependency" => "actions/checkout@v4", "detail" => "pinned SHA is not an ancestor of the ref" }
      end

      it "is treated as the same unresolvable class" do
        expect(error).to be_a(Dependabot::GithubActions::Lockfile::UnresolvableDependency)
      end
    end

    # These are the PRE-fix diagnosis of conditions a `check` fix-mode pass resolves
    # (re-pin / prune / normalize) or refuses-as-skip. They appear in findings even
    # on a successful run — the load-bearing case is a v1->v2 bump that exits 1 only
    # because a sibling workflow refused onboarding, yet still re-pinned on disk — so
    # they must NOT block the relock.
    %w(misleading-sha ref-moved ref-changed not-pinned sha-as-ref stale).each do |category|
      context "with a #{category} finding (auto-resolved by fix-mode)" do
        let(:finding) do
          { "category" => category, "severity" => "error", "action" => "actions/cache@v3", "detail" => "boom" }
        end

        it "does not block — the lock on disk already reflects the fix" do
          expect(error).to be_nil
        end
      end
    end

    context "with the retired UNREACHABLE category" do
      let(:finding) { { "category" => "UNREACHABLE", "dependency" => "x/y@v1" } }

      it "is no longer recognized as blocking" do
        expect(error).to be_nil
      end
    end

    context "with a confidence-axis category at warning severity" do
      let(:finding) do
        { "category" => "misleading-sha", "severity" => "warning", "dependency" => "x/y@v1", "detail" => "low conf" }
      end

      it "does not block — severity gates, not category" do
        expect(error).to be_nil
      end
    end

    context "with an auto-resolved category at error severity" do
      let(:finding) do
        { "category" => "ref-changed", "severity" => "error", "dependency" => "x/y@v1", "detail" => "moved" }
      end

      it "still does not block — ref-changed is re-pinned by fix-mode, not a survivor" do
        expect(error).to be_nil
      end
    end

    context "with an unresolvable category downgraded to warning severity" do
      let(:finding) do
        { "category" => "impostor-commit", "severity" => "warning", "dependency" => "x/y@v1", "detail" => "d" }
      end

      it "honors the CLI severity and does not block" do
        expect(error).to be_nil
      end
    end

    context "with an unresolvable category and no severity field" do
      let(:finding) { { "category" => "impostor-commit", "dependency" => "x/y@v1", "detail" => "d" } }

      it "falls back to category so known-hard findings still block" do
        expect(error).to be_a(Dependabot::GithubActions::Lockfile::UnresolvableDependency)
      end
    end

    context "with an unknown category not in the blocking vocab" do
      let(:finding) { { "category" => "info-note", "severity" => "warning", "dependency" => "x/y@v1" } }

      it "returns nil so the engine can surface it as a warning" do
        expect(error).to be_nil
      end
    end

    context "with a category that differs only in case" do
      let(:finding) { { "category" => "Impostor-Commit", "dependency" => "x/y@v1", "detail" => "d" } }

      it "matches case-insensitively" do
        expect(error).to be_a(Dependabot::GithubActions::Lockfile::UnresolvableDependency)
      end
    end

    context "with a finding that has no category" do
      let(:finding) { { "severity" => "error", "dependency" => "x/y@v1" } }

      it "returns nil" do
        expect(error).to be_nil
      end
    end

    context "with an onboarding-required finding (severity error)" do
      let(:finding) do
        { "category" => "onboarding-required", "severity" => "error",
          "workflow" => ".github/workflows/b.yml", "detail" => "not tracked" }
      end

      it "returns nil — onboarding-required is a skip, never a raised error" do
        expect(error).to be_nil
      end
    end
  end

  describe ".onboarding_required?" do
    it "is true for the onboarding-required category" do
      expect(described_class.onboarding_required?({ "category" => "onboarding-required" })).to be(true)
    end

    it "matches case-insensitively" do
      expect(described_class.onboarding_required?({ "category" => "Onboarding-Required" })).to be(true)
    end

    it "is false for any blocking category" do
      expect(described_class.onboarding_required?({ "category" => "impostor-commit" })).to be(false)
    end

    it "is false when no category is present" do
      expect(described_class.onboarding_required?({ "severity" => "error" })).to be(false)
    end
  end
end
