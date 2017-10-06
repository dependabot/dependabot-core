# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/file_updaters/ruby/bundler/git_source_remover"

RSpec.describe Dependabot::FileUpdaters::Ruby::Bundler::GitSourceRemover do
  let(:remover) { described_class.new(dependency: dependency) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "df9f605d7111b6814fe493cf8f41de3f9f0978b2",
      requirements: [],
      package_manager: "bundler"
    )
  end

  let(:dependency_name) { "business" }

  describe "#rewrite" do
    subject(:rewrite) { remover.rewrite(content) }

    let(:content) { fixture("ruby", "gemfiles", "git_source") }

    context "with a dependency that specifies a ref" do
      let(:dependency_name) { "business" }
      it "replaces the ref" do
        expect(rewrite).to include(%(gem "business", "~> 1.6.0"\ngem))
      end

      it "leaves other gems alone" do
        expect(rewrite).to include(%(gem "prius", git: "https))
      end
    end

    context "with non-git tags at the start" do
      let(:content) do
        %(gem "business", "1.0.0", require: false, git: "git_url")
      end
      it { is_expected.to eq(%(gem "business", "1.0.0", require: false)) }
    end

    context "with non-git tags at the end" do
      let(:content) do
        %(gem "business", "1.0.0", git: "git_url", require: false)
      end
      it { is_expected.to eq(%(gem "business", "1.0.0", require: false)) }
    end

    context "with non-git tags on a subsequent line" do
      let(:content) do
        %(gem "business", "1.0.0", git: "git_url",\nrequire: false)
      end
      it { is_expected.to eq(%(gem "business", "1.0.0", require: false)) }
    end

    context "with git tags on a subsequent line" do
      let(:content) do
        %(gem "business", "1.0.0", require: false,\ngit: "git_url")
      end
      it { is_expected.to eq(%(gem "business", "1.0.0", require: false)) }
    end

    context "with a custom tag" do
      let(:content) { %(gem "business", "1.0.0", github: "git_url") }
      it { is_expected.to eq(%(gem "business", "1.0.0")) }
    end

    context "with a comment" do
      let(:content) { %(gem "business", "1.0.0", git: "git_url" # My gem) }
      it { is_expected.to eq(%(gem "business", "1.0.0" # My gem)) }
    end
  end
end
