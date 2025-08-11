# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/update_checker"

RSpec.describe Dependabot::Conda::UpdateChecker::RequirementTranslator do
  describe ".conda_to_pip" do
    context "with nil requirement" do
      it "returns nil" do
        expect(described_class.conda_to_pip(nil)).to be_nil
      end
    end

    context "with conda equality requirements" do
      it "converts = to ==" do
        expect(described_class.conda_to_pip("=1.2.3")).to eq("==1.2.3")
      end

      it "converts =1.21.0 to ==1.21.0" do
        expect(described_class.conda_to_pip("=1.21.0")).to eq("==1.21.0")
      end

      it "leaves == unchanged" do
        expect(described_class.conda_to_pip("==1.2.3")).to eq("==1.2.3")
      end
    end

    context "with conda wildcard requirements" do
      it "converts =1.2.* to range" do
        expect(described_class.conda_to_pip("=1.2.*")).to eq(">=1.2.0,<1.3.0")
      end

      it "converts =1.21.* to range" do
        expect(described_class.conda_to_pip("=1.21.*")).to eq(">=1.21.0,<1.22.0")
      end

      it "converts =2.0.* to range" do
        expect(described_class.conda_to_pip("=2.0.*")).to eq(">=2.0.0,<2.1.0")
      end

      it "handles single digit wildcards" do
        expect(described_class.conda_to_pip("=1.*")).to eq(">=1.0,<2.0")
      end
    end

    context "with conda comparison operators" do
      it "leaves >= unchanged" do
        expect(described_class.conda_to_pip(">=1.2.0")).to eq(">=1.2.0")
      end

      it "leaves > unchanged" do
        expect(described_class.conda_to_pip(">1.2.0")).to eq(">1.2.0")
      end

      it "leaves <= unchanged" do
        expect(described_class.conda_to_pip("<=1.2.0")).to eq("<=1.2.0")
      end

      it "leaves < unchanged" do
        expect(described_class.conda_to_pip("<1.2.0")).to eq("<1.2.0")
      end

      it "leaves != unchanged" do
        expect(described_class.conda_to_pip("!=1.2.0")).to eq("!=1.2.0")
      end
    end

    context "with complex conda requirements" do
      it "leaves complex constraints unchanged" do
        expect(described_class.conda_to_pip(">=3.8,<3.11")).to eq(">=3.8,<3.11")
      end

      it "leaves pip-style compatible release unchanged" do
        expect(described_class.conda_to_pip("~=1.2.0")).to eq("~=1.2.0")
      end
    end

    context "with bare version numbers" do
      it "converts bare version to equality" do
        expect(described_class.conda_to_pip("1.2.3")).to eq("==1.2.3")
      end

      it "converts bare major.minor to equality" do
        expect(described_class.conda_to_pip("1.2")).to eq("==1.2")
      end
    end

    context "with edge cases" do
      it "handles empty string" do
        expect(described_class.conda_to_pip("")).to eq("")
      end

      it "handles malformed requirements gracefully" do
        expect(described_class.conda_to_pip("invalid")).to eq("invalid")
      end
    end
  end
end
