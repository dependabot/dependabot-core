require "spec_helper"
require "bumper/dependency"
require "bumper/dependency_file"
require "bumper/update_checkers/ruby_update_checker"

RSpec.describe UpdateCheckers::RubyUpdateChecker do
  before do
    allow(Gem).
      to receive(:latest_version_for).
      with(dependency_name).
      and_return(Gem::Version.new("1.2.0"))
  end

  let(:checker) do
    described_class.new(dependency: dependency,
                        dependency_files: [gemfile, gemfile_lock])
  end

  let(:dependency_version) { "1.2.0" }
  let(:dependency_name) { "business" }
  let(:dependency) do
    Dependency.new(name: dependency_name, version: dependency_version)
  end

  let(:gemfile) { DependencyFile.new(content: gemfile_body, name: "Gemfile") }
  let(:gemfile_body) { fixture("Gemfile") }
  let(:gemfile_lock) do
    DependencyFile.new(content: fixture("Gemfile.lock"), name: "Gemfile.lock")
  end

  describe "#needs_update?" do
    subject { checker.needs_update? }

    context "given an up-to-date dependency" do
      let(:dependency_version) { "1.2.0" }
      it { is_expected.to be_falsey }
    end

    context "given an outdated dependency" do
      let(:dependency_version) { "1.1.0" }
      it { is_expected.to be_truthy }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq("1.2.0") }
  end
end
