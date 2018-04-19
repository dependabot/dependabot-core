# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_updaters/ruby/bundler/gemspec_dependency_name_finder"

module_to_test = Dependabot::FileUpdaters::Ruby::Bundler
RSpec.describe module_to_test::GemspecDependencyNameFinder do
  let(:finder) { described_class.new(gemspec_content: gemspec_content) }
  let(:gemspec_content) { fixture("ruby", "gemspecs", "small_example") }

  describe "#dependency_name" do
    subject(:dependency_name) { finder.dependency_name }

    it { is_expected.to eq("example") }
  end
end
