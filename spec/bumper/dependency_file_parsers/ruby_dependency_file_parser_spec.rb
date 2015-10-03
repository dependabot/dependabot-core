require "spec_helper"
require "bumper/dependency"
require "bumper/dependency_file_parsers/ruby_dependency_file_parser"

RSpec.describe DependencyFileParsers::RubyDependencyFileParser do
  let(:gemfile) { File.read("spec/fixtures/Gemfile") }
  let(:parser) { DependencyFileParsers::RubyDependencyFileParser.new(gemfile) }
  subject(:dependencies) { parser.parse }

  its(:length) { is_expected.to eq(1) }

  describe "the first dependency" do
    subject { dependencies.first }

    it { is_expected.to be_a(Dependency) }
    its(:name) { is_expected.to eq("business") }
    its(:version) { is_expected.to eq("1.4.0") }
  end
end
