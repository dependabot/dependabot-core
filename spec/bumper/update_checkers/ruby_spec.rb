require "spec_helper"
require "./app/dependency"
require "./app/dependency_file"
require "./app/update_checkers/ruby"

RSpec.describe UpdateCheckers::Ruby do
  before do
    stub_request(:get, "https://rubygems.org/api/v1/gems/business.yaml").
      to_return(status: 200, body: fixture("rubygems_response.yaml"))
  end

  let(:checker) do
    described_class.new(dependency: dependency,
                        dependency_files: [gemfile, gemfile_lock])
  end

  let(:dependency) { Dependency.new(name: "business", version: "1.3") }

  let(:gemfile) do
    DependencyFile.new(content: fixture("Gemfile"), name: "Gemfile")
  end
  let(:gemfile_lock) do
    DependencyFile.new(content: gemfile_lock_content, name: "Gemfile.lock")
  end
  let(:gemfile_lock_content) { fixture("Gemfile.lock") }

  describe "#needs_update?" do
    subject { checker.needs_update? }

    context "given an outdated dependency" do
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
      let(:gemfile_lock_content) { fixture("up_to_date_gemfile.lock") }
      it { is_expected.to be_falsey }
    end

    context "given an out-of-date bundler as a dependency" do
      before { allow(checker).to receive(:latest_version).and_return("10.0.0") }
      let(:dependency) { Dependency.new(name: "bundler", version: "1.10.5") }
      let(:gemfile_lock_content) { fixture("gemfile_with_bundler.lock") }

      it { is_expected.to be_truthy }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq("1.5.0") }
  end
end
