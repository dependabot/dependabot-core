# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/requirement"
require "dependabot/npm_and_yarn/version"

RSpec.describe Dependabot::NpmAndYarn::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a comma-separated string" do
      let(:requirement_string) { "^ 4.2.5, >= 4.2.5.1" }

      it { is_expected.to eq(described_class.new([">= 4.2.5", "< 5.0.0.a", ">= 4.2.5.1"])) }
    end

    context "with an exact version specified" do
      let(:requirement_string) { "1.0.0" }

      it { is_expected.to eq(described_class.new("1.0.0")) }
    end

    context "with a dist tag" do
      context "when it is supported tag" do
        let(:requirement_string) { "next" }

        it { expect { requirement }.not_to raise_error }
      end

      context "when it is not supported tag or unknown versioning" do
        let(:requirement_string) { "some_tag" }

        it "raises a bad requirement error" do
          expect { requirement }
            .to raise_error(Gem::Requirement::BadRequirementError)
        end
      end
    end

    context "with a bunch of === specified" do
      let(:requirement_string) { "====1.0.0" }

      it { is_expected.to eq(described_class.new("1.0.0")) }
    end

    context "with a caret version specified" do
      let(:requirement_string) { "^1.0.0" }

      it { is_expected.to eq(described_class.new(">= 1.0.0", "< 2.0.0.a")) }

      context "when dealing with two digits" do
        let(:requirement_string) { "^1.2" }

        it { is_expected.to eq(described_class.new(">= 1.2", "< 2.0.0.a")) }
      end

      context "with an additional equal sign" do
        let(:requirement_string) { "^=1.0.0" }

        it { is_expected.to eq(described_class.new(">= 1.0.0", "< 2.0.0.a")) }
      end

      context "when dealing with two digits with x" do
        let(:requirement_string) { "^1.2.x" }

        it { is_expected.to eq(described_class.new(">= 1.2", "< 2.0.0.a")) }
      end

      context "with a pre-1.0.0 dependency" do
        let(:requirement_string) { "^0.2.3" }

        it { is_expected.to eq(described_class.new(">= 0.2.3", "< 0.3.0.a")) }
      end

      context "with a pre-1.0.0 specifying major.minor.patch version" do
        let(:requirement_string) { "^0.0.3" }

        it { is_expected.to eq(described_class.new(">= 0.0.3", "< 0.0.4")) }
      end

      context "with a pre-1.0.0 specifying major.minor version only" do
        let(:requirement_string) { "^0.0" }

        it { is_expected.to eq(described_class.new(">= 0.0", "< 0.1.0.a")) }
      end

      context "with a pre-1.0.0 specifying major.minor.x version" do
        let(:requirement_string) { "^0.0.x" }

        it { is_expected.to eq(described_class.new(">= 0.0", "< 0.1.0.a")) }
      end

      context "with a pre-1.0.0 specifying major.minor.* version" do
        let(:requirement_string) { "^0.0.*" }

        it { is_expected.to eq(described_class.new(">= 0.0", "< 0.1.0.a")) }
      end

      context "with a pre-1.0.0 specifying major version only" do
        let(:requirement_string) { "^0" }

        it { is_expected.to eq(described_class.new(">= 0", "< 1.0.0.a")) }
      end
    end

    context "with a ~ version specified" do
      let(:requirement_string) { "~1.5.1" }

      its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.5.1").to_s) }

      context "with a pre-1.0.0 specifying major.minor.patch version" do
        let(:requirement_string) { "~0.0.3" }

        it { is_expected.to eq(described_class.new("~> 0.0.3")) }
      end

      context "with an additional equal sign" do
        let(:requirement_string) { "~ =1.5.1" }

        its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.5.1").to_s) }
      end

      context "with a pre-1.0.0 specifying major.minor version only" do
        let(:requirement_string) { "~0.0" }

        it { is_expected.to eq(described_class.new("~> 0.0.0")) }
      end

      context "with a pre-1.0.0 specifying major version only" do
        let(:requirement_string) { "~0" }

        it { is_expected.to eq(described_class.new("~> 0.0")) }
      end
    end

    context "with a hyphen range specified" do
      let(:requirement_string) { "1.0.0 - 1.5.0" }

      it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0", "<= 1.5.0")) }

      context "with a partial starting major.minor version (patch omitted)" do
        let(:requirement_string) { "1.2 - 2.3.4" }

        it { is_expected.to eq(Gem::Requirement.new(">= 1.2.0", "<= 2.3.4")) }
      end

      context "with a partial ending major version (minor and patch omitted)" do
        let(:requirement_string) { "1.2.3 - 2" }

        it { is_expected.to eq(Gem::Requirement.new(">= 1.2.3", "< 3.0.0.a")) }
      end

      context "with a partial ending major.minor version (patch omitted)" do
        let(:requirement_string) { "1.2.3 - 2.3" }

        it { is_expected.to eq(Gem::Requirement.new(">= 1.2.3", "< 2.4.0.a")) }
      end

      context "with a partial ending major.minor.x version" do
        let(:requirement_string) { "1.2.3 - 2.3.x" }

        it { is_expected.to eq(Gem::Requirement.new(">= 1.2.3", "< 2.4.0.a")) }
      end

      context "with a partial ending major.minor.* version" do
        let(:requirement_string) { "1.2.3 - 2.3.*" }

        it { is_expected.to eq(Gem::Requirement.new(">= 1.2.3", "< 2.4.0.a")) }
      end
    end

    context "with a ~> version specified" do
      let(:requirement_string) { "~>1.5.1" }

      its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.5.1").to_s) }

      context "when specified to 2 places" do
        let(:requirement_string) { "~> 0.5" }

        its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 0.5").to_s) }
      end
    end

    context "with a dist tag" do
      context "when it is valid requirement tag" do
        let(:requirement_string) { "next" }

        it { expect { requirement }.not_to raise_error }
      end

      context "when it is illformed requirement" do
        let(:requirement_string) { "++ 2.1.2" }

        it "raises a bad requirement error" do
          expect { requirement }
            .to raise_error(Gem::Requirement::BadRequirementError)
        end
      end

      context "when it is illformed requirement" do
        let(:requirement_string) { "unsupported_tag" }

        it "raises a bad requirement error" do
          expect { requirement }
            .to raise_error(Gem::Requirement::BadRequirementError)
        end
      end
    end

    context "with only a *" do
      let(:requirement_string) { "*" }

      it { is_expected.to eq(Gem::Requirement.new(">= 0")) }
    end

    context "with empty version" do
      let(:requirement_string) { "" }

      it { is_expected.to eq(Gem::Requirement.new(">= 0")) }
    end

    context "with an *" do
      let(:requirement_string) { "1.*" }

      its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.0").to_s) }
    end

    context "with an x" do
      let(:requirement_string) { "^1.1.x" }

      it { is_expected.to eq(described_class.new(">= 1.1", "< 2.0.0.a")) }

      context "with only major version" do
        let(:requirement_string) { "1.x" }

        its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.0").to_s) }
      end

      context "with major.minor version" do
        let(:requirement_string) { "1.2.x" }

        its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.2.0").to_s) }
      end

      context "with only major version (minor * inferred)" do
        let(:requirement_string) { "1" }

        its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.0").to_s) }
      end

      context "with major.minor version (patch * inferred)" do
        let(:requirement_string) { "1.2" }

        its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.2.0").to_s) }
      end
    end

    context "with a 'v' prefix" do
      let(:requirement_string) { ">=v1.0.0" }

      it { is_expected.to eq(described_class.new(">= v1.0.0")) }
    end

    context "with a latest string" do
      let(:requirement_string) { "latest" }

      it { expect { requirement }.not_to raise_error }
    end
  end

  describe "#requirements_array" do
    subject(:reqs) { described_class.requirements_array(requirement_string) }

    context "with multiple intersecting requirements" do
      let(:requirement_string) { ">=1.0.0 <=1.5.0" }

      it { is_expected.to eq([Gem::Requirement.new(">= 1.0.0", "<= 1.5.0")]) }

      context "when requirement string is separated by &&" do
        let(:requirement_string) { ">=1.0.0 && <=1.5.0" }

        it { is_expected.to eq([Gem::Requirement.new(">= 1.0.0", "<= 1.5.0")]) }
      end
    end

    context "with multiple optional requirements" do
      let(:requirement_string) { "^1.0.0 || ^2.0.0" }

      it do
        expect(reqs).to contain_exactly(Gem::Requirement.new(">= 1.0.0", "< 2.0.0.a"),
                                        Gem::Requirement.new(">= 2.0.0", "< 3.0.0.a"))
      end
    end

    context "with parentheses that do nothing" do
      let(:requirement_string) { "(^1.0.0 || ^2.0.0)" }

      it do
        expect(reqs).to contain_exactly(Gem::Requirement.new(">= 1.0.0", "< 2.0.0.a"),
                                        Gem::Requirement.new(">= 2.0.0", "< 3.0.0.a"))
      end
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    context "with a Gem::Version" do
      context "when dealing with the current version" do
        let(:version) { Gem::Version.new("1.0.0") }

        it { is_expected.to be(true) }

        context "when the requirement includes a v-prefix" do
          let(:requirement_string) { ">=v1.0.0" }

          it { is_expected.to be(true) }
        end
      end

      context "when dealing with an out-of-range version" do
        let(:version) { Gem::Version.new("0.9.0") }

        it { is_expected.to be(false) }
      end
    end

    context "with a NpmAndYarn::Version" do
      let(:version) do
        Dependabot::NpmAndYarn::Version.new(version_string)
      end

      context "when dealing with the current version" do
        let(:version_string) { "1.0.0" }

        it { is_expected.to be(true) }

        context "when including a 'v' prefix" do
          let(:version_string) { "v1.0.0" }

          it { is_expected.to be(true) }
        end

        context "when including a local version" do
          let(:version_string) { "1.0.0+gc.1" }

          it { is_expected.to be(true) }
        end

        context "with a 'latest' requirement" do
          let(:requirement_string) { "latest" }

          it { is_expected.to be(false) }
        end
      end
    end
  end
end
