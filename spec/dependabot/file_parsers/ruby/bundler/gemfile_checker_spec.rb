# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_parsers/ruby/bundler/gemfile_checker"

RSpec.describe Dependabot::FileParsers::Ruby::Bundler::GemfileChecker do
  let(:checker) do
    described_class.new(dependency: dependency, gemfile: gemfile)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.3",
      requirements: [{ requirement: "1", file: "a", groups: nil, source: nil }],
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "business" }

  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: "Gemfile")
  end
  let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }

  describe "#includes_dependency?" do
    subject(:includes_dependency) { checker.includes_dependency? }

    context "when the file does not include the dependency" do
      let(:dependency_name) { "dependabot-core" }
      it { is_expected.to eq(false) }
    end

    context "when the file does include the dependency" do
      let(:dependency_name) { "business" }
      it { is_expected.to eq(true) }

      context "but it's in a source block" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "sidekiq_pro") }
        let(:dependency_name) { "sidekiq-pro" }

        it { is_expected.to eq(true) }
      end

      context "but it's in a group block" do
        let(:gemfile_body) do
          fixture("ruby", "gemfiles", "development_dependencies")
        end
        let(:dependency_name) { "business" }

        it { is_expected.to eq(true) }
      end
    end
  end
end
