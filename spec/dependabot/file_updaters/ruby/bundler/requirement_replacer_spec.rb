# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/file_updaters/ruby/bundler/requirement_replacer"

RSpec.describe Dependabot::FileUpdaters::Ruby::Bundler::RequirementReplacer do
  let(:replacer) do
    described_class.new(dependency: dependency, filename: filename)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.5.0",
      previous_version: "1.2.0",
      requirements: requirements,
      package_manager: "bundler"
    )
  end
  let(:requirements) do
    [{ source: nil, file: "Gemfile", requirement: "~> 1.5.0", groups: [] }]
  end

  let(:dependency_name) { "business" }
  let(:filename) { "Gemfile" }

  describe "#rewrite" do
    subject(:rewrite) { replacer.rewrite(content) }

    let(:content) { fixture("ruby", "gemfiles", "git_source") }

    context "with a Gemfile" do
      let(:filename) { "Gemfile" }

      context "when the declaration spans multiple lines" do
        let(:content) { fixture("ruby", "gemfiles", "git_source") }
        it { is_expected.to include(%(gem "business", "~> 1.5.0",\n    git: )) }
        it { is_expected.to include(%(gem "statesman", "~> 1.2.0")) }
      end

      context "within a source block" do
        let(:content) do
          "source 'https://example.com' do\n"\
          "  gem \"business\", \"~> 1.0\", require: true\n"\
          "end"
        end
        it { is_expected.to include(%(gem "business", "~> 1.5.0", require:)) }
      end

      context "with multiple requirements" do
        let(:content) { %(gem "business", "~> 1.0", ">= 1.0.1") }
        it { is_expected.to eq(%(gem "business", "~> 1.5.0")) }

        context "given as an array" do
          let(:content) { %(gem "business", [">= 1", "<3"], require: true) }
          it { is_expected.to eq(%(gem "business", "~> 1.5.0", require: true)) }
        end

        context "for the new requirement" do
          let(:requirements) do
            [
              {
                source: nil,
                file: "Gemfile",
                requirement: ">= 1.0, < 3.0",
                groups: []
              }
            ]
          end

          it { is_expected.to eq(%(gem "business", ">= 1.0", "< 3.0")) }
        end
      end

      context "with a dependency that uses single quotes" do
        let(:content) { %(gem "business", '~> 1.0') }
        it { is_expected.to eq(%(gem "business", '~> 1.5.0')) }
      end

      context "with a dependency that uses quote brackets" do
        let(:content) { %(gem "business", %(1.0)) }
        it { is_expected.to eq(%(gem "business", %(~> 1.5.0))) }
      end
    end
  end
end
