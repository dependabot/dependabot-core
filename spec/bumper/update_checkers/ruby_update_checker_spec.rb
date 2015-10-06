require "spec_helper"
require "bumper/dependency"
require "bumper/dependency_file"
require "bumper/update_checkers/ruby_update_checker"

RSpec.describe UpdateCheckers::RubyUpdateChecker do
  before do
    allow(Gem).
      to receive(:latest_version_for).
      with("business").
      and_return(Gem::Version.new(latest_version))
  end

  let(:latest_version) { "1.4.0" }

  let(:checker) do
    described_class.new(dependency: dependency,
                        dependency_files: [gemfile, gemfile_lock])
  end

  let(:dependency) { Dependency.new(name: "business", version: "1.3") }

  let(:gemfile) do
    DependencyFile.new(content: fixture("Gemfile"), name: "Gemfile")
  end
  let(:gemfile_lock) do
    DependencyFile.new(content: fixture("Gemfile.lock"), name: "Gemfile.lock")
  end

  describe "new" do
    context "when the gemfile.lock is missing" do
      subject { -> { checker } }
      let(:checker) do
        described_class.new(dependency: dependency, dependency_files: [gemfile])
      end

      it { is_expected.to raise_error(/No Gemfile.lock/) }
    end
  end

  describe "#needs_update?" do
    subject { checker.needs_update? }

    context "given an up-to-date dependency" do
      let(:latest_version) { "1.4.0" }
      it { is_expected.to be_falsey }
    end

    context "given an outdated dependency" do
      let(:latest_version) { "1.5.0" }
      it { is_expected.to be_truthy }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(latest_version) }
  end
end
