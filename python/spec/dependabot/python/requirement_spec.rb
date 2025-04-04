# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/requirement"
require "dependabot/python/version"

RSpec.describe Dependabot::Python::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.0.0" }
  let(:version_class) { Dependabot::Python::Version }

  describe ".new" do
    subject(:requirement) { described_class.new(requirement_string) }

    context "with nil" do
      let(:requirement_string) { nil }

      it { is_expected.to eq(described_class.new(">= 0")) }
      it { is_expected.to be_a(described_class) }
    end

    context "with only an *" do
      let(:requirement_string) { "*" }

      it { is_expected.to eq(described_class.new(">= 0")) }
    end

    context "with a ~=" do
      let(:requirement_string) { "~= 1.3.0" }

      its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.3.0").to_s) }
    end

    context "with a ==" do
      let(:requirement_string) { "== 1.3.0" }

      it { is_expected.to be_satisfied_by(Gem::Version.new("1.3.0")) }
      it { is_expected.not_to be_satisfied_by(Gem::Version.new("1.3.1")) }

      context "with a v-prefix" do
        let(:requirement_string) { "== v1.3.0" }

        it { is_expected.to be_satisfied_by(Gem::Version.new("1.3.0")) }
        it { is_expected.not_to be_satisfied_by(Gem::Version.new("1.3.1")) }
      end
    end

    context "with a ===" do
      let(:requirement_string) { "=== 1.3.0" }

      it "implements arbitrary equality" do
        expect(requirement).to be_satisfied_by(version_class.new("1.3.0"))
        expect(requirement).not_to be_satisfied_by(version_class.new("1.3"))
      end
    end

    context "with a ~" do
      let(:requirement_string) { "~1.2.3" }

      its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.2.3").to_s) }

      context "when dealing with two digits" do
        let(:requirement_string) { "~1.2" }

        its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.2.0").to_s) }
      end

      context "when dealing with one digits" do
        let(:requirement_string) { "~1" }

        its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.0").to_s) }
      end
    end

    context "with a ^" do
      let(:requirement_string) { "^1.2.3" }

      it { is_expected.to eq(described_class.new(">= 1.2.3", "< 2.0.0.dev")) }

      context "when dealing with two digits" do
        let(:requirement_string) { "^1.2" }

        it { is_expected.to eq(described_class.new(">= 1.2", "< 2.0.0.dev")) }
      end

      context "with a pre-1.0.0 dependency" do
        let(:requirement_string) { "^0.2.3" }

        it { is_expected.to eq(described_class.new(">= 0.2.3", "< 0.3.0.dev")) }
      end
    end

    context "with an *" do
      let(:requirement_string) { "== 1.3.*" }

      its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.3.0.dev").to_s) }

      context "without a prefix" do
        let(:requirement_string) { "1.3.*" }

        its(:to_s) do
          is_expected.to eq(Gem::Requirement.new("~> 1.3.0.dev").to_s)
        end
      end

      context "with a bad character after the wildcard" do
        let(:requirement_string) { "== 1.3.*'" }

        it "raises a helpful error" do
          expect { requirement }
            .to raise_error(Gem::Requirement::BadRequirementError)
        end
      end

      context "with a >= op" do
        let(:requirement_string) { ">= 1.3.*" }

        it { is_expected.to eq(described_class.new(">= 1.3.dev")) }
      end
    end

    context "with another operator after the first" do
      let(:requirement_string) { ">=2.0<2.1" }

      # Python ignores that second operator!
      it { is_expected.to eq(Gem::Requirement.new(">=2.0")) }

      context "when separated with a comma" do
        let(:requirement_string) { ">=2.0,<2.1" }

        it { is_expected.to eq(Gem::Requirement.new(">=2.0", "<2.1")) }
      end

      context "when separated by whitespace (supported by Poetry)" do
        let(:requirement_string) { ">=2.0 <2.1" }

        it { is_expected.to eq(Gem::Requirement.new(">=2.0", "<2.1")) }
      end
    end

    context "with multiple operators after the first" do
      let(:requirement_string) { ">=2.0<2.1<2.2" }

      # Python ignores operators after the first!
      it { is_expected.to eq(Gem::Requirement.new(">=2.0")) }

      context "when separated with a comma" do
        let(:requirement_string) { ">=2.0,<2.1,<2.2" }

        it { is_expected.to eq(Gem::Requirement.new(">=2.0", "<2.1", "<2.2")) }
      end

      context "when separated by whitespace (supported by Poetry)" do
        let(:requirement_string) { ">=2.0 <2.1 <2.2" }

        it { is_expected.to eq(Gem::Requirement.new(">=2.0", "<2.1", "<2.2")) }
      end
    end

    context "with an array" do
      let(:requirement_string) { ["== 1.3.*", ">= 1.3.1"] }

      its(:to_s) do
        is_expected.to eq(Gem::Requirement.new(["~> 1.3.0.dev", ">= 1.3.1"]).to_s)
      end
    end

    context "with a pre-release version" do
      let(:requirement_string) { "== 1.3.alpha" }

      it { is_expected.to be_satisfied_by(Gem::Version.new("1.3.a")) }
    end

    context "with a wildcard minor version" do
      let(:requirement_string) { "== 1.2.*" }

      its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.2.0.dev").to_s) }
    end

    context "with a wildcard major version" do
      let(:requirement_string) { "== 2.*" }

      it { is_expected.to eq(described_class.new("~> 2.0.dev")) }
    end
  end

  describe ".requirements_array" do
    subject(:requirements_array) do
      described_class.requirements_array(requirement_string)
    end

    context "with a single requirement" do
      let(:requirement_string) { "1.2.1" }

      it { is_expected.to eq([Gem::Requirement.new("1.2.1")]) }
    end

    context "with a illformed parentheses" do
      let(:requirement_string) { "(== 1.2).1" }

      it "raises a helpful error" do
        expect { requirements_array }
          .to raise_error(Gem::Requirement::BadRequirementError)
      end
    end

    context "with an || requirement" do
      let(:requirement_string) { "1.2.1 || >= 1.5.0" }

      it "generates the correct array of requirements" do
        expect(requirements_array)
          .to contain_exactly(Gem::Requirement.new("1.2.1"), Gem::Requirement.new(">= 1.5.0"))
      end

      context "when python-specific requirements are generated" do
        let(:requirement_string) { "^0.8.0 || ^1.2.0" }

        it "generates the correct array of requirements" do
          expect(requirements_array)
            .to contain_exactly(described_class.new("^0.8.0"), described_class.new("^1.2.0"))
        end
      end
    end

    context "with parens wrapping an || requirement" do
      let(:requirement_string) { "(1.2.1 || >= 1.5.0)" }

      it "generates the correct array of requirements" do
        expect(requirements_array)
          .to contain_exactly(Gem::Requirement.new("1.2.1"), Gem::Requirement.new(">= 1.5.0"))
      end
    end

    context "with parens inside an || requirement" do
      let(:requirement_string) { "(1.2.1) || (>= 1.5.0)" }

      it "generates the correct array of requirements" do
        expect(requirements_array)
          .to contain_exactly(Gem::Requirement.new("1.2.1"), Gem::Requirement.new(">= 1.5.0"))
      end
    end

    context "with illformed parentheses inside an || requirement" do
      let(:requirement_string) { "1.2.1) || >= 1.5.0" }

      it "raises a helpful error" do
        expect { requirements_array }
          .to raise_error(Gem::Requirement::BadRequirementError)
      end
    end

    context "with a wildcard minor version" do
      let(:requirement_string) { "1.2.*" }

      it { is_expected.to eq([described_class.new("~> 1.2.0.dev")]) }
    end

    context "with a wildcard major version" do
      let(:requirement_string) { "2.*" }

      it { is_expected.to eq([described_class.new("~> 2.0.dev")]) }
    end
  end

  describe "#satisfied_by?" do
    subject(:requirement_satisfied_by) { requirement.satisfied_by?(version) }

    context "with a Gem::Version" do
      context "when dealing with the current version" do
        let(:version) { Gem::Version.new("1.0.0") }

        it { is_expected.to be(true) }

        context "when the requirement includes a local version" do
          let(:requirement_string) { ">=1.0.0+gc.1" }

          it { is_expected.to be(false) }
        end
      end

      context "when dealing with an out-of-range version" do
        let(:version) { Gem::Version.new("0.9.0") }

        it { is_expected.to be(false) }
      end
    end

    context "with a Python::Version" do
      let(:version) { version_class.new(version_string) }

      context "when dealing with the current version" do
        let(:version_string) { "1.0.0" }

        it { is_expected.to be(true) }

        context "when including a local version" do
          let(:version_string) { "1.0.0+gc.1" }

          it { is_expected.to be(true) }
        end

        context "when the requirement includes a local version" do
          let(:requirement_string) { ">=1.0.0+gc.1" }

          it { is_expected.to be(false) }

          context "when satisfied by the version" do
            let(:version_string) { "1.0.0+gc.2" }

            it { is_expected.to be(true) }
          end
        end
      end

      context "when dealing with an out-of-range version" do
        let(:version_string) { "0.9.0" }

        it { is_expected.to be(false) }
      end

      context "with a wildcard" do
        let(:requirement_string) { "1.8.*" }

        context "when a pre-release" do
          let(:version_string) { "1.8-dev" }

          it { is_expected.to be(true) }
        end

        context "when a full-release" do
          let(:version_string) { "1.8.1" }

          it { is_expected.to be(true) }

          context "when out of range" do
            let(:version_string) { "1.9.1" }

            it { is_expected.to be(false) }
          end
        end

        context "with a minor version" do
          let(:requirement_string) { "1.8.*" }

          context "when a pre-release" do
            let(:version_string) { "1.8-dev" }

            it { is_expected.to be(true) }
          end

          context "when a full-release" do
            let(:version_string) { "1.8.1" }

            it { is_expected.to be(true) }

            context "when out of range" do
              let(:version_string) { "1.9.1" }

              it { is_expected.to be(false) }
            end
          end
        end
      end
    end
  end
end
