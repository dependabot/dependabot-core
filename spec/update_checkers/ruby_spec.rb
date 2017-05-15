# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/update_checkers/ruby"

RSpec.describe Bump::UpdateCheckers::Ruby do
  before do
    stub_request(:get, "https://rubygems.org/api/v1/gems/business.json").
      to_return(status: 200, body: fixture("rubygems_response.json"))
  end

  let(:checker) do
    described_class.new(dependency: dependency,
                        dependency_files: [gemfile, gemfile_lock])
  end

  let(:dependency) do
    Bump::Dependency.new(name: "business", version: "1.3", language: "ruby")
  end

  let(:gemfile) do
    Bump::DependencyFile.new(content: gemfile_content, name: "Gemfile")
  end
  let(:gemfile_lock) do
    Bump::DependencyFile.new(
      content: gemfile_lock_content,
      name: "Gemfile.lock"
    )
  end
  let(:gemfile_content) { fixture("ruby", "gemfiles", "Gemfile") }
  let(:gemfile_lock_content) { fixture("ruby", "lockfiles", "Gemfile.lock") }

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(Gem::Version.new("1.5.0")) }

    context "given a Gemfile with a non-rubygems source" do
      let(:gemfile_lock_content) do
        fixture("ruby", "lockfiles", "specified_source.lock")
      end
      let(:gemfile_content) { fixture("ruby", "gemfiles", "specified_source") }
      let(:gemfury_business_url) do
        "https://repo.fury.io/greysteil/api/v1/dependencies?gems=business"
      end
      before do
        # Note: returns details of three versions: 1.5.0, 1.9.0, and 1.10.0.beta
        stub_request(:get, gemfury_business_url).
          to_return(status: 200, body: fixture("gemfury_response"))
      end

      it { is_expected.to eq(Gem::Version.new("1.9.0")) }
    end

    context "given an unreadable Gemfile" do
      let(:gemfile) do
        Bump::DependencyFile.new(
          content: fixture("ruby", "gemfiles", "includes_requires"),
          name: "Gemfile"
        )
      end

      it "blows up with a useful error" do
        expect { checker.latest_version }.
          to raise_error(Bump::DependencyFileNotEvaluatable)
      end
    end

    context "given a git source" do
      let(:gemfile_lock_content) do
        fixture("ruby", "lockfiles", "git_source.lock")
      end
      let(:gemfile_content) { fixture("ruby", "gemfiles", "git_source") }
      let(:dependency) do
        Bump::Dependency.new(name: "prius", version: "0.9", language: "ruby")
      end

      it { is_expected.to be_nil }
    end

    context "given a Gemfile that specifies a Ruby version" do
      let(:gemfile_content) { fixture("ruby", "gemfiles", "explicit_ruby") }
      it { is_expected.to eq(Gem::Version.new("1.5.0")) }
    end
  end
end
