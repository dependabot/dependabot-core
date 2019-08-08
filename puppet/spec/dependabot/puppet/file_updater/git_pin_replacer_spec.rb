# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/puppet/file_updater/git_pin_replacer"

RSpec.describe Dependabot::Puppet::FileUpdater::GitPinReplacer do
  let(:replacer) do
    described_class.new(dependency: dependency, new_pin: new_pin)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "df9f605d7111b6814fe493cf8f41de3f9f0978b2",
      requirements: [],
      package_manager: "puppet"
    )
  end

  let(:dependency_name) { "puppetlabs/dsc" }
  let(:new_pin) { "new_ref" }

  describe "#rewrite" do
    subject(:rewrite) { replacer.rewrite(content) }

    let(:content) { fixture("puppet", "git_source") }

    context "with a dependency that specifies a ref" do
      it "replaces the ref" do
        expect(rewrite).to include(%(:ref => 'new_ref'\n))
      end

      it "leaves other tags alone" do
        expect(rewrite).to include(%(ref: '1.2.0'))
      end
    end

    context "with a dependency that specifies a tag" do
      let(:content) { fixture("puppet", "git_source").gsub("ref", "tag") }

      it "replaces the tag" do
        expect(rewrite).to include(%(:tag => 'new_ref'))
      end

      it "leaves other tags alone" do
        expect(rewrite).to include(%(tag: '1.2.0'\n))
      end
    end

    context "with a dependency that uses double quotes" do
      let(:content) { %(mod "puppetlabs/dsc", git: "https://x.com", tag: "v1") }
      it "replaces the tag" do
        expect(rewrite).to include(%(tag: "new_ref"))
      end
    end

    context "with a dependency that uses quote brackets" do
      let(:content) do
        %(mod "puppetlabs/dsc", git: "https://x.com", tag: %(v1))
      end

      it "replaces the tag" do
        expect(rewrite).to include(%(tag: %(new_ref)))
      end
    end
  end
end
