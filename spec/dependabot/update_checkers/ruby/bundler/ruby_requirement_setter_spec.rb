# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/update_checkers/ruby/bundler/ruby_requirement_setter"

module_to_test = Dependabot::UpdateCheckers::Ruby::Bundler
RSpec.describe module_to_test::RubyRequirementSetter do
  let(:setter) { described_class.new(gemspec: gemspec) }
  let(:gemspec) do
    Dependabot::DependencyFile.new(content: gemspec_body, name: "some.gemspec")
  end
  let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }

  describe "#rewrite" do
    subject(:rewrite) { setter.rewrite(content) }

    context "when the gemspec does not include a required_ruby_version" do
      let(:gemspec_body) { fixture("ruby", "gemspecs", "no_required_ruby") }
      context "without an existing ruby version" do
        let(:content) { fixture("ruby", "gemfiles", "Gemfile") }
        it { is_expected.to eq(content) }
      end

      context "with an existing ruby version" do
        let(:content) { fixture("ruby", "gemfiles", "explicit_ruby") }
        it { is_expected.to eq(content) }
      end
    end

    context "when the gemspec includes a required_ruby_version" do
      let(:gemspec_body) { fixture("ruby", "gemspecs", "old_required_ruby") }

      context "without an existing ruby version" do
        let(:content) { fixture("ruby", "gemfiles", "Gemfile") }
        it { is_expected.to include("ruby '1.9.3'\n") }
        it { is_expected.to include(%(gem "business", "~> 1.4.0")) }
      end

      context "with an existing ruby version" do
        context "at top level" do
          let(:content) { fixture("ruby", "gemfiles", "explicit_ruby") }

          it { is_expected.to include("ruby '1.9.3'\n") }
          it { is_expected.to_not include(%(ruby "2.2.0")) }
          it { is_expected.to include(%(gem "business", "~> 1.4.0")) }
        end

        context "within a source block" do
          let(:content) do
            "source 'https://example.com' do\n"\
            "  ruby \"2.2.0\"\n"\
            "end"
          end
          it { is_expected.to include("ruby '1.9.3'\n") }
          it { is_expected.to_not include(%(ruby "2.2.0")) }
        end

        context "loaded from a file" do
          let(:content) { fixture("ruby", "gemfiles", "ruby_version_file") }

          it { is_expected.to include("ruby '1.9.3'\n") }
          it { is_expected.to_not include("ruby File.open") }
        end
      end
    end
  end
end
