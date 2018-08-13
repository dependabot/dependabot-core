# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/python/pip/poetry_files_parser"

RSpec.describe Dependabot::FileParsers::Python::Pip::PoetryFilesParser do
  let(:parser) { described_class.new(dependency_files: files) }

  let(:files) { [pyproject] }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: pyproject_body
    )
  end
  let(:pyproject_body) do
    fixture("python", "pyproject_files", pyproject_fixture_name)
  end
  let(:pyproject_fixture_name) { "pyproject.toml" }

  describe "parse" do
    subject(:dependencies) { parser.dependency_set.dependencies }

    context "without a lockfile" do
      its(:length) { is_expected.to eq(15) }

      it "doesn't include the Python requirement" do
        expect(dependencies.map(&:name)).to_not include("python")
      end

      context "with a string declaration" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("geopy")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(
            [{
              requirement: "^1.13",
              file: "pyproject.toml",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with a lockfile" do
      let(:files) { [pyproject, pyproject_lock] }
      let(:pyproject_lock) do
        Dependabot::DependencyFile.new(
          name: "pyproject.lock",
          content: pyproject_lock_body
        )
      end
      let(:pyproject_lock_body) do
        fixture("python", "pyproject_locks", pyproject_lock_fixture_name)
      end
      let(:pyproject_lock_fixture_name) { "pyproject.lock" }

      its(:length) { is_expected.to eq(36) }

      it "doesn't include the Python requirement" do
        expect(dependencies.map(&:name)).to_not include("python")
      end

      context "with a manifest declaration" do
        subject(:dependency) { dependencies.find { |f| f.name == "geopy" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("geopy")
          expect(dependency.version).to eq("1.14.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "^1.13",
              file: "pyproject.toml",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        context "that has a name that needs normalising" do
          subject(:dependency) { dependencies.find { |f| f.name == "pillow" } }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("pillow")
            expect(dependency.version).to eq("5.1.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "^5.1",
                file: "pyproject.toml",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end
      end

      context "without a manifest declaration" do
        subject(:dependency) { dependencies.find { |f| f.name == "appdirs" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("appdirs")
          expect(dependency.version).to eq("1.4.3")
          expect(dependency.requirements).to eq([])
        end
      end
    end
  end
end
