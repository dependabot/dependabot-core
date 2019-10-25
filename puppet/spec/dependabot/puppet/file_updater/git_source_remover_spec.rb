# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/puppet/file_updater/git_source_remover"

RSpec.describe Dependabot::Puppet::FileUpdater::GitSourceRemover do
  let(:remover) { described_class.new(dependency: dependency) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "df9f605d7111b6814fe493cf8f41de3f9f0978b2",
      requirements: [],
      package_manager: "puppet"
    )
  end

  let(:dependency_name) { "puppetlabs/dsc" }

  describe "#rewrite" do
    subject(:rewrite) { remover.rewrite(content) }

    let(:content) { fixture("puppet", "git_source") }

    context "with a dependency that specifies a ref" do
      let(:dependency_name) { "puppetlabs/dsc" }
      it "replaces the ref" do
        expect(rewrite).to include(%(mod "puppetlabs/dsc"\n\nmod))
      end

      it "leaves other gems alone" do
        expect(rewrite).to include(%(mod "puppet/windowsfeature",\n    git:))
      end
    end

    context "with a comment" do
      let(:content) do
        %(mod "puppetlabs/dsc", "1.0.0", git: "git_url" # My gem)
      end
      it { is_expected.to eq(%(mod "puppetlabs/dsc", "1.0.0" # My gem)) }
    end
  end
end
