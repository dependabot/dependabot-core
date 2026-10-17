# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/bundler/file_updater/git_pin_replacer"

RSpec.describe Dependabot::Bundler::FileUpdater::GitPinReplacer do
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

    let(:content) do
      bundler_project_dependency_file("git_source", filename: "Gemfile").content
    end

    context "with a dependency that specifies a ref" do
      let(:dependency_name) { "business" }

      it "replaces the ref" do
        expect(rewrite).to include(%(ref: "new_ref"\n))
      end

      it "leaves other tags alone" do
        expect(rewrite).to include(%(tag: "v0.11.6"))
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

    context "with a dependency declared inside a git block" do
      let(:content) do
        <<~GEMFILE
          git "https://x.com/monorepo", tag: "v1", glob: "gems/*/*.gemspec" do
            gem "business"
          end
        GEMFILE
      end

      it "replaces the tag on the git block" do
        expect(rewrite).to include(%(git "https://x.com/monorepo", tag: "new_ref", glob: "gems/*/*.gemspec" do))
      end
    end

    context "with a dependency declared inside a git block alongside other gems" do
      let(:content) do
        <<~GEMFILE
          git "https://x.com/monorepo", ref: "a1b78a9" do
            gem "statesman"
            gem "business"
          end

          git "https://x.com/other", tag: "v0.11.6" do
            gem "que"
          end
        GEMFILE
      end

      it "replaces the ref on the git block that declares the dependency" do
        expect(rewrite).to include(%(git "https://x.com/monorepo", ref: "new_ref" do))
      end

      it "leaves other git blocks alone" do
        expect(rewrite).to include(%(git "https://x.com/other", tag: "v0.11.6" do))
      end
    end

    context "with a dependency declared inside a github block" do
      let(:content) do
        <<~GEMFILE
          github "org/monorepo", tag: 'v1' do
            gem "business"
          end
        GEMFILE
      end

      it "replaces the tag on the github block" do
        expect(rewrite).to include(%(github "org/monorepo", tag: 'new_ref' do))
      end
    end

    context "with a dependency declared inside a non-git block" do
      let(:content) do
        <<~GEMFILE
          group :development, tag: "v1" do
            gem "business"
          end
        GEMFILE
      end

      it "leaves the block alone" do
        expect(rewrite).to eq(content)
      end
    end
  end
end
