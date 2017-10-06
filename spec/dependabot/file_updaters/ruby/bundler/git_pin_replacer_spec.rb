# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/file_updaters/ruby/bundler/git_pin_replacer"

RSpec.describe Dependabot::FileUpdaters::Ruby::Bundler::GitPinReplacer do
  let(:replacer) do
    described_class.new(dependency: dependency, new_pin: new_pin)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "df9f605d7111b6814fe493cf8f41de3f9f0978b2",
      requirements: [],
      package_manager: "bundler"
    )
  end

  let(:dependency_name) { "business" }
  let(:new_pin) { "new_ref" }

  describe "#rewrite" do
    subject(:rewrite) { replacer.rewrite(content) }

    let(:content) { fixture("ruby", "gemfiles", "git_source") }

    context "with a dependency that specifies a ref" do
      let(:dependency_name) { "business" }
      it "replaces the ref" do
        expect(rewrite).to include(%(ref: "new_ref"\n))
      end

      it "leaves other tags alone" do
        expect(rewrite).to include(%(tag: "v0.11.7"))
      end
    end

    context "with a dependency that specifies a tag" do
      let(:dependency_name) { "que" }
      it "replaces the tag" do
        expect(rewrite).to include(%(tag: "new_ref"))
      end

      it "leaves other tags alone" do
        expect(rewrite).to include(%(ref: "a1b78a9"\n))
      end
    end

    context "with a dependency that uses single quotes" do
      let(:content) { %(gem "business", git: "https://x.com", tag: 'v1') }
      it "replaces the tag" do
        expect(rewrite).to include(%(tag: 'new_ref'))
      end
    end

    context "with a dependency that uses quote brackets" do
      let(:content) { %(gem "business", git: "https://x.com", tag: %(v1)) }
      it "replaces the tag" do
        expect(rewrite).to include(%(tag: %(new_ref)))
      end
    end
  end
end
