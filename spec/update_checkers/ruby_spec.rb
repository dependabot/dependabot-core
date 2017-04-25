# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/update_checkers/ruby"

RSpec.describe Bump::UpdateCheckers::Ruby do
  before do
    stub_request(:get, "https://rubygems.org/api/v1/gems/business.json").
      to_return(status: 200, body: fixture("rubygems_response.json"))
    stub_request(:get, gemfury_business_url).
      to_return(status: 200, body: fixture("gemfury_response"))
  end
  let(:gemfury_business_url) do
    "https://repo.fury.io/greysteil/api/v1/dependencies?gems=business"
  end

  let(:checker) do
    described_class.new(dependency: dependency,
                        dependency_files: [gemfile, gemfile_lock])
  end

  let(:dependency) { Bump::Dependency.new(name: "business", version: "1.3") }

  let(:gemfile) do
    Bump::DependencyFile.new(
      content: fixture("ruby", "gemfiles", "Gemfile"), name: "Gemfile"
    )
  end
  let(:gemfile_lock) do
    Bump::DependencyFile.new(
      content: gemfile_lock_content,
      name: "Gemfile.lock"
    )
  end
  let(:gemfile_lock_content) { fixture("ruby", "lockfiles", "Gemfile.lock") }

  describe "#needs_update?" do
    subject { checker.needs_update? }

    context "given an outdated dependency" do
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
      let(:gemfile_lock_content) do
        fixture("ruby", "lockfiles", "up_to_date_gemfile.lock")
      end
      it { is_expected.to be_falsey }
    end

    context "given a dependency that doesn't appear in the lockfile" do
      let(:dependency) { Bump::Dependency.new(name: "x", version: "1.0") }
      it { is_expected.to be_falsey }
    end

    context "given an out-of-date bundler as a dependency" do
      before { allow(checker).to receive(:latest_version).and_return("10.0.0") }
      let(:dependency) do
        Bump::Dependency.new(name: "bundler", version: "1.10.5")
      end
      let(:gemfile_lock_content) do
        fixture("ruby", "lockfiles", "gemfile_with_bundler.lock")
      end

      it { is_expected.to be_truthy }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq("1.5.0") }

    context "given a lockfile with a non-rubygems source" do
      let(:gemfile_lock_content) do
        fixture("ruby", "lockfiles", "specified_source.lock")
      end
      let(:gemfile) do
        Bump::DependencyFile.new(
          content: fixture("ruby", "gemfiles", "specified_source"),
          name: "Gemfile"
        )
      end

      it { is_expected.to eq("1.9.0") }
    end
  end
end
