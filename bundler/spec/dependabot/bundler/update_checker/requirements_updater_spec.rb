# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/update_checker/requirements_updater"

RSpec.describe Dependabot::Bundler::UpdateChecker::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      update_strategy: update_strategy,
      latest_version: latest_version,
      latest_resolvable_version: latest_resolvable_version,
      updated_source: updated_source
    )
  end

  let(:requirements) { [gemfile_requirement, gemspec_requirement].compact }
  let(:gemfile_requirement) do
    {
      file: "Gemfile",
      requirement: gemfile_requirement_string,
      groups: gemfile_groups,
      source: nil
    }
  end
  let(:gemspec_requirement) do
    {
      file: "some.gemspec",
      requirement: gemspec_requirement_string,
      groups: gemspec_groups,
      source: nil
    }
  end
  let(:gemfile_requirement_string) { "~> 1.4.0" }
  let(:gemfile_groups) { [] }
  let(:gemspec_requirement_string) { "~> 1.4.0" }
  let(:gemspec_groups) { [] }
  let(:updated_source) { nil }

  let(:update_strategy) { :bump_versions }
  let(:latest_version) { "1.8.0" }
  let(:latest_resolvable_version) { "1.5.0" }

  describe "#updated_requirements" do
    subject(:updated_requirements) { updater.updated_requirements }

    context "when there were no requirements" do
      let(:requirements) { [] }
      it { is_expected.to eq([]) }
    end

    context "for a Gemfile dependency" do
      subject { updated_requirements.find { |r| r[:file] == "Gemfile" } }

      context "when there is no resolvable version" do
        let(:latest_resolvable_version) { nil }
        it { is_expected.to eq(gemfile_requirement) }
      end

      context "with a SHA-1 version" do
        before { gemfile_requirement.merge!(source: { type: "git" }) }
        let(:updated_source) { { type: "git" } }

        its([:requirement]) { is_expected.to eq("~> 1.5.0") }
        its([:source]) { is_expected.to eq(type: "git") }

        context "when asked to remove a git source" do
          let(:updated_source) { nil }
          its([:source]) { is_expected.to be_nil }

          context "when no update to the requirements is required" do
            let(:gemfile_requirement_string) { ">= 0" }
            it { is_expected.to eq(gemfile_requirement.merge(source: nil)) }
          end
        end

        context "when asked to update a git reference" do
          let(:updated_source) { { type: "git", ref: "v1.5.0" } }
          before do
            gemfile_requirement.merge!(source: { type: "git", ref: "v1.2.0" })
          end
          its([:source]) { is_expected.to eq(updated_source) }
        end
      end

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { "1.5.0" }

        context "and a full version was previously specified" do
          let(:gemfile_requirement_string) { "~> 1.4.0" }
          its([:requirement]) { is_expected.to eq("~> 1.5.0") }
          its([:file]) { is_expected.to eq("Gemfile") }

          context "in a gems.rb" do
            subject { updated_requirements.find { |r| r[:file] == "gems.rb" } }
            before { gemfile_requirement[:file] = "gems.rb" }

            its([:requirement]) { is_expected.to eq("~> 1.5.0") }
            its([:file]) { is_expected.to eq("gems.rb") }
          end
        end

        context "and it's a pre-release" do
          let(:latest_resolvable_version) { "1.5.0.beta" }
          let(:gemfile_requirement_string) { "~> 1.4.0" }
          its([:requirement]) { is_expected.to eq("~> 1.5.0.beta") }
        end

        context "and a pre-release was previously specified" do
          let(:gemfile_requirement_string) { "~> 1.5.0.beta" }
          its([:requirement]) { is_expected.to eq("~> 1.5.0") }

          context "at 2dp, updating to a later pre-release" do
            let(:gemfile_requirement_string) { "~> 1.5.beta" }
            let(:latest_resolvable_version) { "1.5.0.beta2" }
            its([:requirement]) { is_expected.to eq("~> 1.5.beta2") }
          end

          context "at 4dp, updating to a later pre-release" do
            let(:gemfile_requirement_string) { "~> 1.5.0.beta.1" }
            let(:latest_resolvable_version) { "1.5.0.beta.2" }
            its([:requirement]) { is_expected.to eq("~> 1.5.0.beta.2") }
          end
        end

        context "and a minor version was previously specified" do
          let(:gemfile_requirement_string) { "~> 1.4" }
          its([:requirement]) { is_expected.to eq("~> 1.5") }
        end

        context "and a greater than or equal to matcher was used" do
          let(:gemfile_requirement_string) { ">= 1.4.0" }
          its([:requirement]) { is_expected.to eq(">= 1.4.0") }
        end

        context "and a less than matcher was used" do
          let(:gemfile_requirement_string) { "< 1.4.0" }
          its([:requirement]) { is_expected.to eq("< 1.6.0") }
        end

        context "for a library" do
          let(:update_strategy) { :bump_versions_if_necessary }

          context "and the new version satisfies the old requirements" do
            let(:gemfile_requirement_string) { "~> 1.4" }
            it { is_expected.to eq(gemfile_requirement) }
          end

          context "and the new version does not satisfy the old requirements" do
            let(:gemfile_requirement_string) { "~> 1.4.0" }
            its([:requirement]) { is_expected.to eq("~> 1.5.0") }
          end

          context "when there are multiple requirements" do
            context "one of which is exact" do
              let(:gemfile_requirement_string) { "= 1.0.0, <= 1.4.0" }
              its([:requirement]) { is_expected.to eq("1.5.0") }
            end

            context "one of which is a ~>" do
              context "that are already satisfied" do
                let(:gemfile_requirement_string) { "~> 1.0, >= 1.0.1" }
                its([:requirement]) { is_expected.to eq("~> 1.0, >= 1.0.1") }
              end

              context "that are not already satisfied" do
                let(:gemfile_requirement_string) { "~> 0.9, >= 0.9.1" }
                its([:requirement]) { is_expected.to eq("~> 1.5") }
              end
            end

            context "forming a range" do
              let(:gemfile_requirement_string) { ">= 1.0, < 1.4" }
              its([:requirement]) { is_expected.to eq(">= 1.0, < 1.6") }

              context "with a precision mismatch" do
                let(:gemfile_requirement_string) { ">= 1.0, < 1.4.2.2" }
                its([:requirement]) { is_expected.to eq(">= 1.0, < 1.5.1") }
              end

              context "which shouldn't be resolvable..." do
                let(:gemfile_requirement_string) { ">= 2.0, < 2.4" }

                it "raises a useful error" do
                  expect { updated_requirements }.
                    to raise_error(/Unexpected operation/)
                end
              end
            end

            context "with a != matcher" do
              context "that binds" do
                let(:gemfile_requirement_string) { ">= 1.0, != 1.5.0" }
                its([:requirement]) { is_expected.to eq(">= 1.0") }
              end

              context "that does not bind" do
                let(:gemfile_requirement_string) { ">= 1.0, != 1.4.0, < 1.3" }
                its([:requirement]) do
                  is_expected.to eq(">= 1.0, != 1.4.0, < 1.6")
                end
              end
            end
          end
        end

        context "when there are multiple requirements" do
          context "one of which is exact" do
            let(:gemfile_requirement_string) { "= 1.0.0, <= 1.4.0" }
            its([:requirement]) { is_expected.to eq("1.5.0") }
          end

          context "one of which is a ~>" do
            context "that are already satisfied" do
              let(:gemfile_requirement_string) { "~> 1.0, >= 1.0.1" }
              its([:requirement]) { is_expected.to eq("~> 1.5") }
            end
          end
        end
      end

      context "with multiple Gemfile declarations" do
        before { requirements << child_gemfile_requirement }
        let(:child_gemfile_requirement) do
          gemfile_requirement.merge(file: "backend/Gemfile")
        end

        describe "the first Gemfile" do
          subject { updated_requirements.find { |r| r[:file] == "Gemfile" } }
          its([:requirement]) { is_expected.to eq("~> 1.5.0") }
        end

        describe "the child Gemfile" do
          subject do
            updated_requirements.find { |r| r[:file] == "backend/Gemfile" }
          end

          its([:requirement]) { is_expected.to eq("~> 1.5.0") }
        end
      end
    end

    context "for a gemspec dependency" do
      subject { updated_requirements.find { |r| r[:file].end_with?("emspec") } }

      context "when there is no latest version" do
        let(:latest_version) { nil }
        it { is_expected.to eq(gemspec_requirement) }
      end

      context "when there is no resolvable version" do
        let(:latest_resolvable_version) { nil }
        it { is_expected.to eq(gemspec_requirement) }
      end

      context "when there is a latest version" do
        let(:latest_version) { "1.8.0" }
        let(:latest_resolvable_version) { "1.5.0" }

        context "when an = specifier was used" do
          let(:gemspec_requirement_string) { "= 1.4.0" }
          its([:requirement]) { is_expected.to eq("= 1.5.0") }

          context "and the version is greater" do
            let(:gemspec_requirement_string) { "1.7.0" }
            its([:requirement]) { is_expected.to eq("= 1.7.0") }
          end
        end

        context "when no specifier was used" do
          let(:gemspec_requirement_string) { "1.4.0" }
          its([:requirement]) { is_expected.to eq("= 1.5.0") }
        end

        context "when a < specifier was used" do
          let(:gemspec_requirement_string) { "< 1.4.0" }
          its([:requirement]) { is_expected.to eq("< 1.9.0") }
        end

        context "when a <= specifier was used" do
          let(:gemspec_requirement_string) { "<= 1.4.0" }
          its([:requirement]) { is_expected.to eq("<= 1.9.0") }
        end

        context "when a ~> specifier was used" do
          let(:gemspec_requirement_string) { "~> 1.4.0" }
          its([:requirement]) { is_expected.to eq(">= 1.4, < 1.9") }

          context "with two zeros" do
            let(:gemspec_requirement_string) { "~> 1.0.0" }
            its([:requirement]) { is_expected.to eq(">= 1.0, < 1.9") }
          end

          context "with no zeros" do
            let(:gemspec_requirement_string) { "~> 1.0.1" }
            its([:requirement]) { is_expected.to eq(">= 1.0.1, < 1.9.0") }
          end

          context "with minor precision" do
            let(:gemspec_requirement_string) { "~> 0.1" }
            its([:requirement]) { is_expected.to eq(">= 0.1, < 2.0") }
          end

          context "with major precision" do
            let(:latest_version) { "2.8.0" }
            let(:gemspec_requirement_string) { "~> 1" }
            its([:requirement]) { is_expected.to eq(">= 1, < 3") }

            context "and a 0 version" do
              let(:gemspec_requirement_string) { "~> 0" }
              its([:requirement]) { is_expected.to eq("< 3") }
            end
          end
        end

        context "when there are multiple requirements" do
          let(:gemspec_requirement_string) { "> 1.0.0, <= 1.4.0" }
          its([:requirement]) { is_expected.to eq("> 1.0.0, <= 1.9.0") }

          context "that could cause duplication" do
            let(:gemspec_requirement_string) { "~> 0.5, >= 0.5.2" }
            its([:requirement]) { is_expected.to eq(">= 0.5.2, < 2.0") }
          end

          context "and one is a != requirement" do
            context "that is binding" do
              let(:gemspec_requirement_string) { "~> 1.4, != 1.8.0" }
              its([:requirement]) { is_expected.to eq("~> 1.4") }
            end

            context "that is not binding" do
              let(:gemspec_requirement_string) { "~> 1.4.0, != 1.5.0" }
              its([:requirement]) do
                is_expected.to eq(">= 1.4, != 1.5.0, < 1.9")
              end
            end
          end
        end

        context "when a beta version was used in the old requirement" do
          let(:gemspec_requirement_string) { "< 1.4.0.beta" }
          its([:requirement]) { is_expected.to eq("< 1.9.0") }
        end

        context "when a != specifier was used" do
          let(:gemspec_requirement_string) { "!= 1.8.0" }
          its([:requirement]) { is_expected.to eq(">= 0") }
        end

        context "when a >= specifier was used" do
          let(:gemspec_requirement_string) { ">= 1.9.0" }
          its([:requirement]) { is_expected.to eq(:unfixable) }
        end

        context "when a > specifier was used" do
          let(:gemspec_requirement_string) { "> 1.8.0" }
          its([:requirement]) { is_expected.to eq(:unfixable) }
        end

        context "for a development dependency" do
          let(:requirements) do
            [{
              file: "some.gemspec",
              requirement: gemspec_requirement_string,
              groups: ["development"],
              source: nil
            }]
          end

          context "when an = specifier was used" do
            let(:gemspec_requirement_string) { "= 1.4.0" }
            its([:requirement]) { is_expected.to eq("= 1.5.0") }
          end

          context "when no specifier was used" do
            let(:gemspec_requirement_string) { "1.4.0" }
            its([:requirement]) { is_expected.to eq("= 1.5.0") }
          end

          context "when a < specifier was used" do
            let(:gemspec_requirement_string) { "< 1.4.0" }
            its([:requirement]) { is_expected.to eq("< 1.9.0") }
          end

          context "when a <= specifier was used" do
            let(:gemspec_requirement_string) { "<= 1.4.0" }
            its([:requirement]) { is_expected.to eq("<= 1.9.0") }
          end

          context "when a ~> specifier was used" do
            let(:gemspec_requirement_string) { "~> 1.4.0" }
            its([:requirement]) { is_expected.to eq("~> 1.5.0") }

            context "with minor precision" do
              let(:gemspec_requirement_string) { "~> 0.1" }
              its([:requirement]) { is_expected.to eq("~> 1.5") }
            end
          end

          context "when there are multiple requirements" do
            let(:gemspec_requirement_string) { "> 1.0.0, <= 1.4.0" }
            its([:requirement]) { is_expected.to eq("> 1.0.0, <= 1.9.0") }
          end

          context "when a beta version was used in the old requirement" do
            let(:gemspec_requirement_string) { "< 1.4.0.beta" }
            its([:requirement]) { is_expected.to eq("< 1.9.0") }
          end

          context "when a != specifier was used" do
            let(:gemspec_requirement_string) { "!= 1.5.0" }
            its([:requirement]) { is_expected.to eq(">= 0") }
          end

          context "when a >= specifier was used" do
            let(:gemspec_requirement_string) { ">= 1.6.0" }
            its([:requirement]) { is_expected.to eq(:unfixable) }
          end

          context "when a > specifier was used" do
            let(:gemspec_requirement_string) { "> 1.6.0" }
            its([:requirement]) { is_expected.to eq(:unfixable) }
          end
        end
      end
    end

    context "with both a Gemfile and a gemspec" do
      let(:gemfile_requirement_string) { "~> 1.4.0" }
      let(:gemfile_groups) { [] }
      let(:gemspec_requirement_string) { ">= 1.0, < 1.5" }
      let(:gemspec_groups) { [] }

      it "updates both files" do
        expect(updated_requirements).to match_array(
          [{
            file: "Gemfile",
            requirement: "~> 1.5.0",
            groups: [],
            source: nil
          }, {
            file: "some.gemspec",
            requirement: ">= 1.0, < 1.9",
            groups: [],
            source: nil
          }]
        )
      end

      context "and an updated source" do
        let(:updated_source) { { type: "git", ref: "v1.5.0" } }
        let(:gemfile_requirement) do
          {
            file: "Gemfile",
            requirement: gemfile_requirement_string,
            groups: gemfile_groups,
            source: gemfile_source
          }
        end
        let(:gemspec_requirement) do
          {
            file: "some.gemspec",
            requirement: gemspec_requirement_string,
            groups: gemspec_groups,
            source: gemspec_source
          }
        end
        let(:gemfile_source) { { type: "git", ref: "v1.4.0" } }
        let(:gemspec_source) { { type: "git", ref: "v1.4.0" } }

        it "updates both files" do
          expect(updated_requirements).to match_array(
            [{
              file: "Gemfile",
              requirement: "~> 1.5.0",
              groups: [],
              source: { type: "git", ref: "v1.5.0" }
            }, {
              file: "some.gemspec",
              requirement: ">= 1.0, < 1.9",
              groups: [],
              source: { type: "git", ref: "v1.5.0" }
            }]
          )
        end

        context "when the original gemspec source was `nil`" do
          let(:gemspec_source) { nil }

          it "leaves the gemspec source as `nil`" do
            expect(updated_requirements).to match_array(
              [{
                file: "Gemfile",
                requirement: "~> 1.5.0",
                groups: [],
                source: { type: "git", ref: "v1.5.0" }
              }, {
                file: "some.gemspec",
                requirement: ">= 1.0, < 1.9",
                groups: [],
                source: nil
              }]
            )
          end
        end
      end
    end

    context "when lockfile_only configured" do
      let(:update_strategy) { :lockfile_only }

      it "does not change any requirements" do
        expect(updated_requirements).to eq(requirements)
      end
    end
  end
end
