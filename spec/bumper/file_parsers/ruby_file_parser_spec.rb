require "spec_helper"
require "bumper/dependency"
require "bumper/file_parsers/ruby_file_parser"

RSpec.describe FileParsers::RubyFileParser do
  let(:gemfile) { File.read("spec/fixtures/Gemfile") }
  let(:parser) { FileParsers::RubyFileParser.new(gemfile) }
  subject(:dependencies) { parser.parse }

  its(:length) { is_expected.to eq(1) }

  describe "the first dependency" do
    subject { dependencies.first }

    it { is_expected.to be_a(Dependency) }
    its(:name) { is_expected.to eq("business") }
    its(:version) { is_expected.to eq("1.4.0") }
  end
end
