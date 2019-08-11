# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/puppet/file_updater/puppetfile_updater"

RSpec.describe Dependabot::Puppet::FileUpdater::PuppetfileUpdater do
  let(:updater) do
    described_class.new(dependencies: dependencies, puppetfile: puppetfile)
  end
  let(:dependencies) { [dependency] }
  let(:puppetfile) do
    Dependabot::DependencyFile.new(name: "Puppetfile", content: puppetfile_body)
  end
  let(:puppetfile_body) { fixture("puppet", puppetfile_fixture_name) }
  let(:puppetfile_fixture_name) { "Puppetfile" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      previous_version: dependency_previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "puppet"
    )
  end
  let(:dependency_name) { "puppetlabs/dsc" }
  let(:dependency_version) { "1.9.0" }
  let(:dependency_previous_version) { "1.4.0" }
  let(:requirements) do
    [{ file: "Puppetfile", requirement: "1.9.0", groups: [], source: nil }]
  end
  let(:previous_requirements) do
    [{ file: "Puppetfile", requirement: "1.4.0", groups: [], source: nil }]
  end

  describe "#updated_puppetfile_content" do
    subject(:updated_puppetfile_content) { updater.updated_puppetfile_content }

    context "when no change is required" do
      let(:puppetfile_fixture_name) { "version_not_specified" }
      let(:requirements) do
        [{ file: "Puppetfile", requirement: nil, groups: [], source: nil }]
      end
      let(:previous_requirements) do
        [{ file: "Puppetfile", requirement: nil, groups: [], source: nil }]
      end
      it { is_expected.to eq(puppetfile_body) }
    end

    context "when the full version is specified" do
      let(:puppetfile_fixture_name) { "Puppetfile" }
      let(:requirements) do
        [{ file: "Puppetfile", requirement: "1.9.0", groups: [], source: nil }]
      end
      let(:previous_requirements) do
        [{ file: "Puppetfile", requirement: "1.4.0", groups: [], source: nil }]
      end

      it { is_expected.to include("mod \"puppetlabs/dsc\", '1.9.0'") }
      it { is_expected.to include("mod \"puppet/windowsfeature\",  \"2.0.0\"") }
    end

    context "when there is a comment" do
      let(:puppetfile_fixture_name) { "comments" }
      it { is_expected.to include "mod \"puppetlabs/dsc\", '1.9.0'    # This " }
    end

    context "with multiple dependencies" do
      let(:puppetfile_fixture_name) { "Puppetfile" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "puppetlabs/dsc",
            version: "1.9.0",
            requirements: [{
              file: "Puppetfile",
              requirement: "1.9.0",
              groups: [],
              source: nil
            }],
            previous_version: "1.4.0",
            previous_requirements: [{
              file: "Puppetfile",
              requirement: "1.4.0",
              groups: [],
              source: nil
            }],
            package_manager: "puppet"
          ),
          Dependabot::Dependency.new(
            name: "puppet/windowsfeature",
            version: "3.2.0",
            requirements: [{
              file: "Puppetfile",
              requirement: "3.2.0",
              groups: [],
              source: nil
            }],
            previous_version: "2.0.0",
            previous_requirements: [{
              file: "Puppetfile",
              requirement: "2.0.0",
              groups: [],
              source: nil
            }],
            package_manager: "puppet"
          )
        ]
      end

      it "updates both dependencies" do
        expect(updated_puppetfile_content).
          to include(%(mod "puppetlabs/dsc", '1.9.0'\n))
        expect(updated_puppetfile_content).
          to include(%(mod "puppet/windowsfeature",  "3.2.0"\n))
      end
    end

    context "with a module that has a git source" do
      let(:puppetfile_body) do
        %(mod "puppetlabs/dsc", ) +
          %(git: "https://github.com/puppetlabs/dsc", tag: "v1.0.0"\n)
      end
      let(:previous_requirements) do
        [{
          file: "Puppetfile",
          requirement: nil,
          groups: [],
          source: {
            type: "git",
            url: "http://github.com/puppetlabs/dsc",
            ref: "v1.0.0"
          }
        }]
      end
      let(:dependency_previous_version) do
        "c170ea081c121c00ed6fe8764e3557e731454b9d"
      end

      context "that should have its tag updated" do
        let(:puppetfile_body) do
          %(mod "puppetlabs/dsc", ) +
            %(git: "https://github.com/puppetlabs/dsc", tag: "v1.0.0")
        end
        let(:previous_requirements) do
          [{
            file: "Puppetfile",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "http://github.com/puppetlabs/dsc",
              ref: "v1.0.0"
            }
          }]
        end
        let(:requirements) do
          [{
            file: "Puppetfile",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "http://github.com/puppetlabs/dsc",
              ref: "v1.8.0"
            }
          }]
        end

        let(:expected_string) do
          %(mod "puppetlabs/dsc", ) +
            %(git: "https://github.com/puppetlabs/dsc", tag: "v1.8.0")
        end

        it { is_expected.to eq(expected_string) }
      end

      context "that should be removed" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "puppetlabs/dsc",
            version: "1.8.0",
            previous_version: "c5bf1bd47935504072ac0eba1006cf4d67af6a7a",
            requirements: requirements,
            previous_requirements: previous_requirements,
            package_manager: "puppet"
          )
        end
        let(:requirements) do
          [{
            file: "Puppetfile",
            requirement: "1.8.0",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to include "\"puppetlabs/dsc\", \"1.8.0\"\n" }

        context "with a tag (i.e., multiple git-related arguments)" do
          let(:puppetfile_body) do
            %(mod "puppetlabs/dsc", git: "git_url", tag: "old_tag")
          end
          it { is_expected.to eq(%(mod "puppetlabs/dsc", "1.8.0")) }
        end

        context "with git args on a subsequent line" do
          let(:puppetfile_body) do
            %(mod "puppetlabs/dsc", '1.0.0', \ngit: "git_url")
          end
          it do
            is_expected.to eq(%(mod "puppetlabs/dsc", '1.8.0'))
          end
        end

        context "with a custom arg" do
          let(:puppetfile_body) do
            %(mod "puppetlabs/dsc", "1.0.0", github: "git_url")
          end
          it { is_expected.to eq(%(mod "puppetlabs/dsc", "1.8.0")) }
        end

        context "with a comment" do
          let(:puppetfile_body) do
            %(mod "puppetlabs/dsc", git: "git_url" # My gem)
          end
          it { is_expected.to eq(%(mod "puppetlabs/dsc", "1.8.0" # My gem)) }
        end
      end
    end
  end
end
