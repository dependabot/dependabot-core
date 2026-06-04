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
    end

    context "with a tilde requirement" do
      it { expect(satisfied?("~1.2.0", "1.2.9")).to be(true) }
      it { expect(satisfied?("~1.2.0", "1.3.0")).to be(false) }
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

    context "with a wildcard" do
      it { expect(satisfied?("*", "9.9.9")).to be(true) }
    end
  end
end
