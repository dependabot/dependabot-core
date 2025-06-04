# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/requirement"

RSpec.describe Dependabot::GoModules::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a blank string" do
      let(:requirement_string) { "" }

      it { is_expected.to eq(described_class.new(">= 0")) }
    end

    context "with a 'v' prefix" do
      let(:requirement_string) { ">=v1.0.0" }

      it { is_expected.to eq(described_class.new(">= v1.0.0")) }
    end

    context "with an 'incompatible' suffix" do
      let(:requirement_string) { ">=v1.0.0+incompatible" }

      it { is_expected.to eq(described_class.new(">= v1.0.0+incompatible")) }
    end

    context "with a pre-release" do
      let(:requirement_string) { "4.0.0-beta3" }

      it "preserves the pre-release formatting" do
        expect(requirement.requirements.first.last.to_s).to eq("4.0.0-beta3")
      end
    end

    describe "wildcards" do
      context "with only a *" do
        let(:requirement_string) { "*" }

        it { is_expected.to eq(described_class.new(">= 0")) }
      end

      context "with a 1.*" do
        let(:requirement_string) { "1.*" }

        it { is_expected.to eq(described_class.new(">= 1.0, < 2.0.0.a")) }

        context "with two wildcards" do
          let(:requirement_string) { "1.*.*" }

          it { is_expected.to eq(described_class.new(">= 1.0.0, < 2.0.0.a")) }
        end

        context "when dealing with a pre-1.0.0 release" do
          let(:requirement_string) { "0.*" }

          it { is_expected.to eq(described_class.new(">= 0.0, < 1.0.0.a")) }
        end
      end

      context "with a 1.*.1" do
        let(:requirement_string) { "1.*.1" }

        it { is_expected.to eq(described_class.new(">= 1.0.0, < 2.0.0.a")) }
      end

      context "with a 1.1.*" do
        let(:requirement_string) { "1.1.*" }

        it { is_expected.to eq(described_class.new(">= 1.1.0", "< 2.0.0.a")) }

        context "when prefixed with a caret" do
          let(:requirement_string) { "^1.1.*" }

          it { is_expected.to eq(described_class.new(">= 1.1.0", "< 2.0.0.a")) }

          context "when dealing with a pre-1.0.0 release" do
            let(:requirement_string) { "^0.0.*" }

            it do
              expect(requirement).to eq(described_class.new(">= 0.0.0", "< 1.0.0.a"))
            end

            context "with a pre-release specifier" do
              let(:requirement_string) { "^0.0.*-alpha" }

              it "maintains a pre-release specifier" do
                expect(requirement)
                  .to eq(described_class.new(">= 0.0.0-a", "< 1.0.0.a"))
              end
            end
          end
        end

        context "when prefixed with a ~" do
          let(:requirement_string) { "~1.1.x" }

          it { is_expected.to eq(described_class.new("~> 1.1.0")) }

          context "with two wildcards" do
            let(:requirement_string) { "~1.x.x" }

            it { is_expected.to eq(described_class.new("~> 1.0")) }
          end
        end

        context "when prefixed with a <" do
          let(:requirement_string) { "<1.1.X" }

          it { is_expected.to eq(described_class.new("< 1.2.0")) }
        end
      end
    end

    context "with no specifier" do
      let(:requirement_string) { "1.1.0" }

      it { is_expected.to eq(described_class.new(">= 1.1.0", "< 2.0.0.a")) }

      context "when there is a v-prefix" do
        let(:requirement_string) { "v1.1.0" }

        it { is_expected.to eq(described_class.new(">= 1.1.0", "< 2.0.0.a")) }
      end
    end

    context "with a caret version" do
      context "when specified to 3 dp" do
        let(:requirement_string) { "^1.2.3" }

        it { is_expected.to eq(described_class.new(">= 1.2.3", "< 2.0.0.a")) }

        context "with a zero major" do
          let(:requirement_string) { "^0.2.3" }

          it { is_expected.to eq(described_class.new(">= 0.2.3", "< 1.0.0.a")) }

          context "when there is a zero minor" do
            let(:requirement_string) { "^0.0.3" }

            it do
              expect(requirement).to eq(described_class.new(">= 0.0.3", "< 1.0.0.a"))
            end
          end
        end
      end

      context "when specified to 2 dp" do
        let(:requirement_string) { "^1.2" }

        it { is_expected.to eq(described_class.new(">= 1.2", "< 2.0.0.a")) }

        context "with a zero major" do
          let(:requirement_string) { "^0.2" }

          it { is_expected.to eq(described_class.new(">= 0.2", "< 1.0.0.a")) }

          context "when there is a zero minor" do
            let(:requirement_string) { "^0.0" }

            it { is_expected.to eq(described_class.new(">= 0.0", "< 1.0.0.a")) }
          end
        end
      end

      context "when specified to 1 dp" do
        let(:requirement_string) { "^1" }

        it { is_expected.to eq(described_class.new(">= 1", "< 2.0.0.a")) }

        context "with a zero major" do
          let(:requirement_string) { "^0" }

          it { is_expected.to eq(described_class.new(">= 0", "< 1.0.0.a")) }
        end
      end
    end

    context "with a ~ version" do
      context "when specified to 3 dp" do
        let(:requirement_string) { "~1.5.1" }

        it { is_expected.to eq(described_class.new("~> 1.5.1")) }
      end

      context "when specified to 2 dp" do
        let(:requirement_string) { "~1.5" }

        it { is_expected.to eq(described_class.new("~> 1.5.0")) }
      end

      context "when specified to 1 dp" do
        let(:requirement_string) { "~1" }

        it { is_expected.to eq(described_class.new("~> 1.0")) }
      end
    end

    context "with a > version specified" do
      let(:requirement_string) { ">1.5.1" }

      it { is_expected.to eq(Gem::Requirement.new("> 1.5.1")) }
    end

    context "with a range literal specified" do
      let(:requirement_string) { "1.1.1 - 1.2.0" }

      it { is_expected.to eq(Gem::Requirement.new(">= 1.1.1", "<= 1.2.0")) }
    end

    context "with an = version specified" do
      let(:requirement_string) { "=1.5" }

      it { is_expected.to eq(Gem::Requirement.new("1.5")) }
    end

    context "with a != version specified" do
      let(:requirement_string) { "!=1.5" }

      it { is_expected.to eq(Gem::Requirement.new("!=1.5")) }
    end

    context "with an ~> version specified" do
      let(:requirement_string) { "~> 1.5.1" }

      its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.5.1").to_s) }
    end

    context "with a comma separated list" do
      let(:requirement_string) { ">1.5.1, < 2.0.0" }

      it { is_expected.to eq(Gem::Requirement.new("> 1.5.1", "< 2.0.0")) }
    end
  end

  describe ".requirements_array" do
    subject(:requirements) do
      described_class.requirements_array(requirement_string)
    end

    context "with a single requirement" do
      let(:requirement_string) { ">=1.0.0" }

      it { is_expected.to eq([described_class.new(">= 1.0.0")]) }
    end

    context "with an OR requirement" do
      let(:requirement_string) { "^1.1.0 || ^2.1.0" }

      it "returns an array of requirements" do
        expect(requirements).to contain_exactly(described_class.new(">= 1.1.0", "< 2.0.0.a"),
                                                described_class.new(">= 2.1.0", "< 3.0.0.a"))
      end
    end
  end
end
