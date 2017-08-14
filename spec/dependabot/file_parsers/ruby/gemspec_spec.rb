# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/ruby/gemspec"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Ruby::Gemspec do
  it_behaves_like "a dependency file parser"

  let(:files) { [gemspec] }
  let(:gemspec) do
    Dependabot::DependencyFile.new(
      name: "business.gemspec",
      content: gemspec_content
    )
  end
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }
    let(:gemspec_content) { fixture("ruby", "gemspecs", "example") }

    its(:length) { is_expected.to eq(11) }

    describe "the first dependency" do
      subject { dependencies.first }

      it { is_expected.to be_a(Dependabot::Dependency) }
      its(:name) { is_expected.to eq("bundler") }
      its(:requirement) { is_expected.to eq(">= 1.12.0") }
      its(:groups) { is_expected.to eq(["runtime"]) }
    end

    describe "the last dependency" do
      subject { dependencies.last }

      it { is_expected.to be_a(Dependabot::Dependency) }
      its(:name) { is_expected.to eq("rake") }
      its(:requirement) { is_expected.to eq(">= 0") }
      its(:groups) { is_expected.to eq(["development"]) }
    end

    context "with a gemspec that requires in other files" do
      let(:gemspec_content) { fixture("ruby", "gemspecs", "with_require") }

      its(:length) { is_expected.to eq(11) }
    end

    context "that can't be evaluated" do
      let(:gemspec_content) { fixture("ruby", "gemspecs", "unevaluatable") }

      it "raises a Dependabot::DependencyFileNotEvaluatable error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end
  end
end
