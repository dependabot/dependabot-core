# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/haskell/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Haskell::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:files) { [cabal_file] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:cabal_file) do
    Dependabot::DependencyFile.new(
      content: cabal_file_body,
      name: "Cabal.cabal"
    )
  end
  let(:cabal_file_body) { fixture("cabal_files", "Cabal.cabal") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "actions/setup-node",
      version: "5273d0df9c603edc4284ac8402cf650b4f1f6686",
      previous_version: nil,
      requirements: [{
        requirement: nil,
        groups: [],
        file: "Cabal.cabal",
        source: nil,
        metadata: { declaration_string: "acme-missiles == 0.3" }
      }],
      previous_requirements: [{
        requirement: nil,
        groups: [],
        file: "Cabal.cabal",
        source: nil,
        metadata: { declaration_string: "acme-missiles == 0.2" }
      }],
      package_manager: "haskell"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated cabal file" do
      subject(:updated_cabal_file) do
        updated_files.find { |f| f.name == "Cabal.cabal" }
      end

      its(:content) do
        is_expected.to include "\"actions/setup-node == 1.1.0\"\n"
        is_expected.to_not include "\"actions/setup-node@master\""
      end

      its(:content) do
        is_expected.to include "'actions/setup-node == 1.1.0'\n"
        is_expected.to_not include "'actions/setup-node@master'"
      end

      its(:content) do
        is_expected.to include "actions/setup-node == 1.1.0\n"
        is_expected.to_not include "actions/setup-node@master"
      end

      its(:content) { is_expected.to include "acme-missiles@master\n" }

      context "with a path" do
        let(:cabal_file_body) do
          fixture("cabal_files", "Cabal.cabal")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "parsec",
            version: "5273d0df9c603edc4284ac8402cf650b4f1f6686",
            previous_version: nil,
            requirements: [{
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              source: nil,
              metadata: { declaration_string: "parsec@main" }
            }, {
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              source: nil,
              metadata: { declaration_string: "parsec@master" }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              source: nil,
              metadata: { declaration_string: "acme-missiles == 0.2" }
            }, {
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              source: nil,
              metadata: { declaration_string: "parsec@master" }
            }],
            package_manager: "haskell"
          )
        end

        its(:content) { is_expected.to include "parsec == 1.1.0\n" }
        its(:content) { is_expected.to include "parsec == 1.1.0\n" }
        its(:content) { is_expected.to_not include "parsec@master" }
        its(:content) { is_expected.to include "acme-missiles@master\n" }
      end

      context "with multiple sources" do
        let(:cabal_file_body) do
          fixture("cabal_files", "multiple_sources.yml")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "acme-missiles",
            version: nil,
            package_manager: "haskell",
            previous_version: nil,
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              metadata: { declaration_string: "acme-missiles == 0.2" },
              source: nil
            }, {
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              metadata: { declaration_string: "acme-missiles@master" },
              source: nil
            }],
            requirements: [{
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              metadata: { declaration_string: "acme-missiles == 2.2.0" },
              source: nil
            }, {
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              metadata: { declaration_string: "acme-missiles@master" },
              source: nil
            }]
          )
        end

        it "updates both sources" do
          expect(subject.content).to include "acme-missiles == 2.2.0\n"
          expect(subject.content).not_to include "acme-missiles@master\n"
        end
      end

      context "with multiple sources matching major version" do
        let(:cabal_file_body) do
          fixture("cabal_files", "multiple_sources_matching_major.yml")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "lens",
            version: nil,
            package_manager: "haskell",
            previous_version: nil,
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              metadata: { declaration_string: "lens == 1" },
              source: nil
            }, {
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              metadata: { declaration_string: "lens == 1.1.2" },
              source: nil
            }],
            requirements: [{
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              metadata: { declaration_string: "lens == 2" },
              source: nil
            }, {
              requirement: nil,
              groups: [],
              file: "Cabal.cabal",
              metadata: { declaration_string: "lens == 1.1.2" },
              source: nil
            }]
          )
        end

        it "updates both sources" do
          expect(subject.content).to include "lens == 2 # comment"
          expect(subject.content).to match(%r{lens == 2$})
          expect(subject.content).not_to include "lens == 1.1.2\n"
          expect(subject.content).not_to include "lens == 2.1.2\n"
        end
      end
    end
  end
end
