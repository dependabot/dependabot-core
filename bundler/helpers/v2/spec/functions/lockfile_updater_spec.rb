# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the child-context-only conservative and dependencies fixtures.

require "native_spec_helper"
require "shared_contexts"

RSpec.describe Functions::LockfileUpdater do
  include_context "when in a temporary bundler directory"
  include_context "when stubbing rubygems compact index"

  let(:project_name) { "conservative_update" }
  let(:lockfile_updater) do
    described_class.new(
      gemfile_name: "Gemfile",
      lockfile_name: "Gemfile.lock",
      dependencies: dependencies,
      conservative: conservative
    )
  end
  let(:dependencies) do
    [{
      "name" => dependency_name,
      "version" => dependency_version,
      "requirements" => [{ "file" => "Gemfile", "requirement" => ">= 0", "groups" => [:default], "source" => nil }]
    }]
  end

  describe "#run" do
    subject(:updated_lockfile) do
      in_tmp_folder { lockfile_updater.run }
    end

    context "when updating a gem whose sub-dependencies have newer versions" do
      let(:dependency_name) { "ibandit" }
      let(:dependency_version) { "1.1.0" }

      context "without conservative updates" do
        let(:conservative) { false }

        it "updates the gem and its sub-dependencies" do
          expect(updated_lockfile).to include("ibandit (1.1.0)")
          expect(updated_lockfile).to include("i18n (1.8.3)")
          expect(updated_lockfile).to include("concurrent-ruby (1.1.6)")
        end
      end

      context "with conservative updates" do
        let(:conservative) { true }

        it "updates the gem and keeps its sub-dependencies at the locked versions" do
          expect(updated_lockfile).to include("ibandit (1.1.0)")
          expect(updated_lockfile).to include("i18n (1.5.1)")
          expect(updated_lockfile).to include("concurrent-ruby (1.1.5)")
        end

        it "leaves unrelated gems untouched" do
          expect(updated_lockfile).to include("dummy-pkg-a (1.0.0)")
          expect(updated_lockfile).to include("dummy-pkg-b (1.0.0)")
        end
      end
    end

    context "when the new version needs a newer sub-dependency" do
      let(:dependency_name) { "dummy-pkg-b" }
      let(:dependency_version) { "1.1.0" }

      context "with conservative updates" do
        let(:conservative) { true }

        it "still moves the sub-dependency" do
          expect(updated_lockfile).to include("dummy-pkg-b (1.1.0)")
          expect(updated_lockfile).to include("dummy-pkg-a (2.0.0)")
          expect(updated_lockfile).to include("i18n (1.5.1)")
        end
      end
    end
  end
end
