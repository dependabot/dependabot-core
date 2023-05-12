# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_change_builder"
require "dependabot/job"

RSpec.describe Dependabot::DependencyChangeBuilder do
  let(:job) do
    instance_double(Dependabot::Job,
                    package_manager: "bundler",
                    repo_contents_path: nil,
                    credentials: [
                      {
                        "type" => "git_source",
                        "host" => "github.com",
                        "username" => "x-access-token",
                        "password" => "github-token"
                      }
                    ],
                    experiments: {})
  end

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("bundler/original/Gemfile"),
        directory: "/"
      ),
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("bundler/original/Gemfile.lock"),
        directory: "/"
      )
    ]
  end

  let(:updated_dependencies) do
    [
      Dependabot::Dependency.new(
        name: "dummy-pkg-b",
        package_manager: "bundler",
        version: "1.2.0",
        previous_version: "1.1.0",
        requirements: [
          {
            file: "Gemfile",
            requirement: "~> 1.2.0",
            groups: [],
            source: nil
          }
        ],
        previous_requirements: [
          {
            file: "Gemfile",
            requirement: "~> 1.1.0",
            groups: [],
            source: nil
          }
        ]
      )
    ]
  end

  describe "::create_from" do
    subject(:create_change) do
      described_class.create_from(
        job: job,
        dependency_files: dependency_files,
        updated_dependencies: updated_dependencies,
        change_source: change_source
      )
    end

    context "when the source is a lead dependency" do
      let(:change_source) do
        Dependabot::Dependency.new(
          name: "dummy-pkg-b",
          package_manager: "bundler",
          version: "1.1.0",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.1.0",
              groups: [],
              source: nil
            }
          ]
        )
      end

      it "creates a new DependencyChange with the updated files" do
        dependency_change = create_change

        expect(dependency_change).to be_a(Dependabot::DependencyChange)
        expect(dependency_change.updated_dependencies).to eql(updated_dependencies)
        expect(dependency_change.updated_dependency_files.map(&:name)).to eql(["Gemfile", "Gemfile.lock"])
        expect(dependency_change).not_to be_grouped_update

        gemfile = dependency_change.updated_dependency_files.find { |file| file.name == "Gemfile" }
        expect(gemfile.content).to eql(fixture("bundler/updated/Gemfile"))

        lockfile = dependency_change.updated_dependency_files.find { |file| file.name == "Gemfile.lock" }
        expect(lockfile.content).to eql(fixture("bundler/updated/Gemfile.lock"))
      end
    end

    context "when the source is a dependency group" do
      let(:change_source) do
        # FIXME: rules are actually a hash but for the purposes of this pass we can leave it as a list
        # Once this is refactored we should create a DependencyGroup like so
        # Dependabot::DependencyGroup.new(name: "dummy-pkg-*", rules: { "patterns" => ["dummy-pkg-*"] })
        Dependabot::DependencyGroup.new(name: "dummy-pkg-*", rules: ["dummy-pkg-*"])
      end

      it "creates a new DependencyChange flagged as a grouped update" do
        dependency_change = create_change

        expect(dependency_change).to be_a(Dependabot::DependencyChange)
        expect(dependency_change).to be_grouped_update
      end
    end
  end
end
