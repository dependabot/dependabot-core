# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/helm/requirement"
require "dependabot/helm/version"

RSpec.describe Dependabot::Helm::Requirement do
  def satisfied?(req_string, version_string)
    described_class.requirements_array(req_string)
                   .any? { |r| r.satisfied_by?(Dependabot::Helm::Version.new(version_string)) }
  end

  describe ".requirements_array / #satisfied_by?" do
    context "with a caret requirement" do
      it { expect(satisfied?("^1.0.0", "1.0.5")).to be(true) }
      it { expect(satisfied?("^1.0.0", "1.9.9")).to be(true) }
      it { expect(satisfied?("^1.0.0", "2.0.0")).to be(false) }
      it { expect(satisfied?("^1.0.0", "1.0.0")).to be(true) }

      context "with a 0.x version (caret pins the minor)" do
        it { expect(satisfied?("^0.2.0", "0.2.9")).to be(true) }
        it { expect(satisfied?("^0.2.0", "0.3.0")).to be(false) }
      end

      context "with a 0.0.x version (caret pins the patch)" do
        it { expect(satisfied?("^0.0.3", "0.0.3")).to be(true) }
        it { expect(satisfied?("^0.0.3", "0.0.4")).to be(false) }
        it { expect(satisfied?("^0.0.3", "0.1.0")).to be(false) }
      end
    end

    context "with a tilde requirement" do
      it { expect(satisfied?("~1.2.0", "1.2.9")).to be(true) }
      it { expect(satisfied?("~1.2.0", "1.3.0")).to be(false) }

      context "with the ~> spelling" do
        it { expect(satisfied?("~>1.2.0", "1.2.9")).to be(true) }
        it { expect(satisfied?("~>1.2.0", "1.3.0")).to be(false) }
      end
    end

    context "with a hyphen range (inclusive both ends)" do
      it { expect(satisfied?("1.0.0 - 2.0.0", "1.5.0")).to be(true) }
      it { expect(satisfied?("1.0.0 - 2.0.0", "1.0.0")).to be(true) }
      it { expect(satisfied?("1.0.0 - 2.0.0", "2.0.0")).to be(true) }
      it { expect(satisfied?("1.0.0 - 2.0.0", "2.0.1")).to be(false) }
      it { expect(satisfied?("1.0.0 - 2.0.0", "0.9.0")).to be(false) }

      context "with a partial upper bound (x-range semantics)" do
        # "1.0 - 2.0" includes the whole 2.0.x series, so 2.0.0 must satisfy it
        # (regression: a zero last component was previously not incremented).
        it { expect(satisfied?("1.0 - 2.0", "2.0.0")).to be(true) }
        it { expect(satisfied?("1.0 - 2.0", "2.0.5")).to be(true) }
        it { expect(satisfied?("1.0 - 2.0", "2.1.0")).to be(false) }
        it { expect(satisfied?("1.2.3 - 2", "2.9.9")).to be(true) }
        it { expect(satisfied?("1.2.3 - 2", "3.0.0")).to be(false) }
      end
    end

    context "with an explicit range (space-AND)" do
      it { expect(satisfied?(">=1.0.0 <2.0.0", "1.5.0")).to be(true) }
      it { expect(satisfied?(">=1.0.0 <2.0.0", "2.0.0")).to be(false) }
    end

    context "with a comma-separated range (Masterminds comma-AND)" do
      it { expect(satisfied?(">=1.0.0, <2.0.0", "1.5.0")).to be(true) }
      it { expect(satisfied?(">=1.0.0, <2.0.0", "2.0.0")).to be(false) }
    end

    context "with an OR range" do
      it { expect(satisfied?("^1.0.0 || ^2.0.0", "2.5.0")).to be(true) }
      it { expect(satisfied?("^1.0.0 || ^2.0.0", "1.5.0")).to be(true) }
      it { expect(satisfied?("^1.0.0 || ^2.0.0", "3.0.0")).to be(false) }
    end

    context "with an exact version" do
      it { expect(satisfied?("1.0.0", "1.0.0")).to be(true) }
      it { expect(satisfied?("1.0.0", "1.0.1")).to be(false) }
    end

    context "with an x-range" do
      it { expect(satisfied?("1.x", "1.9.0")).to be(true) }
      it { expect(satisfied?("1.x", "2.0.0")).to be(false) }
    end

    context "with a comparator applied to a wildcard (Masterminds semantics)" do
      # Boundaries verified against the Go Masterminds/semver library.
      it { expect(satisfied?("<=1.x", "1.5.0")).to be(true) }
      it { expect(satisfied?("<=1.x", "1.9.9")).to be(true) }
      it { expect(satisfied?("<=1.x", "2.0.0")).to be(false) }
      it { expect(satisfied?("<1.x", "0.9.0")).to be(true) }
      it { expect(satisfied?("<1.x", "1.0.0")).to be(false) }
      it { expect(satisfied?(">=1.x", "1.0.0")).to be(true) }
      it { expect(satisfied?(">=1.x", "0.9.0")).to be(false) }
      it { expect(satisfied?(">1.x", "2.0.0")).to be(true) }
      it { expect(satisfied?(">1.x", "1.9.9")).to be(false) }
      it { expect(satisfied?("<=1.2.x", "1.2.9")).to be(true) }
      it { expect(satisfied?("<=1.2.x", "1.3.0")).to be(false) }
    end

    context "with a wildcard" do
      it { expect(satisfied?("*", "9.9.9")).to be(true) }

      it "treats an operator-prefixed bare wildcard as match-anything" do
        expect { described_class.requirements_array("^*") }.not_to raise_error
        expect(satisfied?("^*", "9.9.9")).to be(true)
      end
    end

    context "with build metadata / digest (Helm OCI charts)" do
      it "parses an exact +digest constraint without raising" do
        expect { described_class.requirements_array("1.0.119807+abc123") }.not_to raise_error
      end

      it { expect(satisfied?("1.0.119807+abc123", "1.0.119807+abc123")).to be(true) }
      it { expect(satisfied?(">=1.0.0+abc", "1.5.0")).to be(true) }
      it { expect(satisfied?("^1.0.0+abc", "1.5.0")).to be(true) }
      it { expect(satisfied?("^1.0.0+abc", "2.0.0")).to be(false) }
    end

    context "with a nil requirement" do
      it "matches anything (does not raise)" do
        req = described_class.requirements_array(nil).first
        expect(req.satisfied_by?(Dependabot::Helm::Version.new("9.9.9"))).to be(true)
      end
    end

    # Round-trip invariant: any version string Helm::Version accepts as an exact
    # pin must parse as a requirement and be satisfied by itself. This guards the
    # class of bug where one component supports a version shape (prerelease,
    # +digest, multi-part) that the requirement parser does not.
    #
    # NOTE: a capital-"V" prefix (e.g. "V1.2.3") is deliberately excluded — like
    # npm, the parser only accepts a lowercase "v", and the updater treats
    # capital-prefixed strings as dist-tags and leaves them untouched.
    describe "round-trip: Helm::Version-valid pins parse and self-satisfy" do
      %w(
        1.0.0 1.2 1 1.2.3.4
        1.2.3-rc1 1.2.3-alpha.1 1.0.0-beta1
        1.0.119807+abc123 1.2.3-rc1+build.5 1.2.3+21AF26D3
        v1.2.3
      ).each do |ver|
        it "round-trips #{ver}" do
          expect { described_class.requirements_array(ver) }.not_to raise_error
          expect(satisfied?(ver, ver)).to be(true)
        end
      end
    end
  end
end
