# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/bundler/file_updater/git_pin_replacer"

RSpec.describe Dependabot::Bundler::FileUpdater::GitPinReplacer do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Bundler::FileUpdater::GitPinReplacer) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:replacer) do
    described_class.new(dependency: dependency, new_pin: new_pin)
  end

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "df9f605d7111b6814fe493cf8f41de3f9f0978b2",
      requirements: [],
      package_manager: "bundler"
    )
  end

  sig { returns(String) }
  let(:dependency_name) { "business" }
  sig { returns(String) }
  let(:new_pin) { "new_ref" }
  # rubocop:enable RSpec/ScatteredLet

  describe "#rewrite" do
    sig { returns(String) }
    subject(:rewrite) { replacer.rewrite(content) }

    sig { returns(String) }
    let(:content) do
      T.must(bundler_project_dependency_file("git_source", filename: "Gemfile").content)
    end

    context "with a dependency that specifies a ref" do
      sig { returns(String) }
      let(:dependency_name) { "business" }

      it "replaces the ref" do
        expect(rewrite).to include(%(ref: "new_ref"\n))
      end

      it "leaves other tags alone" do
        expect(rewrite).to include(%(tag: "v0.11.6"))
      end
    end

    context "with a dependency that specifies a tag" do
      sig { returns(String) }
      let(:dependency_name) { "que" }

      it "replaces the tag" do
        expect(rewrite).to include(%(tag: "new_ref"))
      end

      it "leaves other tags alone" do
        expect(rewrite).to include(%(ref: "a1b78a9"\n))
      end
    end

    context "with a dependency that uses single quotes" do
      sig { returns(String) }
      let(:content) { %(gem "business", git: "https://x.com", tag: 'v1') }

      it "replaces the tag" do
        expect(rewrite).to include(%(tag: 'new_ref'))
      end
    end

    context "with a dependency that uses quote brackets" do
      sig { returns(String) }
      let(:content) { %(gem "business", git: "https://x.com", tag: %(v1)) }

      it "replaces the tag" do
        expect(rewrite).to include(%(tag: %(new_ref)))
      end
    end
  end
end
