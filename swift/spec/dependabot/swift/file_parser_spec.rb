# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/swift/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Swift::FileParser do
  it_behaves_like "a dependency file parser"

  let(:parser) do
    described_class.new(dependency_files: files, source: source)
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/Example",
      directory: "/"
    )
  end

  let(:files) do
    [
      package_manifest_file, 
      package_resolved_file
    ]
  end

  let(:package_manifest_file) do
    Dependabot::DependencyFile.new(
      name: "Package.swift", 
      content: fixture("github", "mona", "Example", "Package.swift")
    )
  end

  let(:package_resolved_file) do
    Dependabot::DependencyFile.new(
      name: "Package.resolved", 
      content: fixture("github", "mona", "Example", "Package.resolved")
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with hosted sources" do
      its(:length) { is_expected.to eq(7) }

      describe "the first dependency (https://github.com/mona/LinkedList.git from 1.2.0)" do
        subject(:dependency) { dependencies[0] }

        let(:expected_requirements) do
          [">= 1.2.0", "< 2.0.0"].map do |requirement|
            {
              requirement: requirement,
              groups: ["dependencies"],
              file: "Package.swift",
              source: {
                type: "repository",
                url: "https://github.com/mona/LinkedList.git"
              }
            }
          end
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("mona.linkedlist")
          expect(dependency.version).to eq("1.2.2")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the second dependency (https://github.com/mona/Queue up to next major from 1.1.1)" do
        subject(:dependency) { dependencies[1] }

        let(:expected_requirements) do
          [">= 1.1.1", "< 2.0.0"].map do |requirement|
            {
              requirement: requirement,
              groups: ["dependencies"],
              file: "Package.swift",
              source: {
                type: "repository",
                url: "https://github.com/mona/Queue"
              }
            }
          end
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("mona.queue")
          expect(dependency.version).to eq("1.5.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the third dependency (https://github.com/mona/HashMap.git up to next minor from 0.9.0)" do
        subject(:dependency) { dependencies[2] }

        let(:expected_requirements) do
          [">= 0.9.0", "< 0.10.0"].map do |requirement|
            {
              requirement: requirement,
              groups: ["dependencies"],
              file: "Package.swift",
              source: {
                type: "repository",
                url: "https://github.com/mona/HashMap.git"
              }
            }
          end
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("mona.hashmap")
          expect(dependency.version).to eq("0.9.9")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the fourth dependency (git@github.com:mona/Matrix.git up to next minor from 2.0.1)" do
        subject(:dependency) { dependencies[3] }

        let(:expected_requirements) do
          [">= 2.0.1", "< 2.1.0"].map do |requirement|
            {
              requirement: requirement,
              groups: ["dependencies"],
              file: "Package.swift",
              source: {
                type: "repository",
                url: "git@github.com:mona/Matrix.git"
              }
            }
          end
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("mona.matrix")
          expect(dependency.version).to eq("2.0.1")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the fifth dependency (ssh://git@github.com:mona/RedBlackTree.git up to next minor from 0.1.0)" do
        subject(:dependency) { dependencies[4] }

        let(:expected_requirements) do
          [">= 0.1.0", "< 0.2.0"].map do |requirement|
            {
              requirement: requirement,
              groups: ["dependencies"],
              file: "Package.swift",
              source: {
                type: "repository",
                url: "ssh://git@github.com:mona/RedBlackTree.git"
              }
            }
          end
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("mona.redblacktree")
          expect(dependency.version).to eq("0.1.10")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the fifth dependency (https://github.com/mona/Heap on main branch)" do
        subject(:dependency) { dependencies[5] }

        let(:expected_requirements) do
          []
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("mona.heap")
          expect(dependency.version).to eq(nil)
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the seventh dependency (https://github.com:443/mona/Trie.git at revision f3b37c3ccf0a1559d4097e2eeb883801c4b8f510)" do
        subject(:dependency) { dependencies[6] }

        let(:expected_requirements) do
          []
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("mona.trie")
          expect(dependency.version).to eq(nil)
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end
  end
end
