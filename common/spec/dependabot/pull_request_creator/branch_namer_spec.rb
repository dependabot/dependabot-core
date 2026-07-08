# typed: false
# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/branch_namer"

RSpec.describe Dependabot::PullRequestCreator::BranchNamer do
  subject(:namer) do
    described_class.new(
      dependencies: dependencies,
      files: files,
      target_branch: target_branch
    )
  end

  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      previous_version: previous_version,
      package_manager: "dummy",
      requirements: requirements,
      previous_requirements: previous_requirements
    )
  end
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.5.0" }
  let(:requirements) do
    [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }]
  end
  let(:previous_requirements) do
    [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
  end
  let(:previous_version) { "1.4.0" }
  let(:files) { [gemfile] }
  let(:target_branch) { nil }

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: fixture("ruby", "gemfiles", "Gemfile")
    )
  end

  describe "#new_branch_name" do
    subject(:new_branch_name) { namer.new_branch_name }

    it { is_expected.to eq("dependabot/dummy/business-1.5.0") }

    context "with directory" do
      let(:gemfile) do
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("ruby", "gemfiles", "Gemfile"),
          directory: directory
        )
      end
      let(:directory) { "directory" }

      it { is_expected.to eq("dependabot/dummy/directory/business-1.5.0") }

      context "when the directory name starts with a dot" do
        let(:directory) { ".directory" }

        it "sanitizes the dot" do
          expect(new_branch_name)
            .to eq("dependabot/dummy/dot-directory/business-1.5.0")
        end
      end
    end

    context "with a custom prefix" do
      let(:namer) do
        described_class.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch,
          prefix: prefix
        )
      end
      let(:prefix) { "myapp" }

      it { is_expected.to eq("myapp/dummy/business-1.5.0") }
    end

    context "with a target branch" do
      let(:target_branch) { "my-branch" }

      it { is_expected.to eq("dependabot/dummy/my-branch/business-1.5.0") }
    end

    context "with a custom branch name separator" do
      let(:namer) do
        described_class.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch,
          separator: "-"
        )
      end

      it { is_expected.to eq("dependabot-dummy-business-1.5.0") }
    end

    context "with a maximum length" do
      let(:namer) do
        described_class.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch,
          max_length: max_length
        )
      end

      context "with a maximum length longer than branch name" do
        let(:max_length) { 35 }

        it { is_expected.to eq("dependabot/dummy/business-1.5.0") }
        its(:length) { is_expected.to eq(31) }
      end

      context "with a maximum length shorter than branch name" do
        let(:dependency_name) { "business-and-work-and-desks-and-tables-and-chairs-and-lunch" }

        context "with a maximum length longer than sha1 length" do
          let(:max_length) { 50 }

          it { is_expected.to eq("dependabot#{Digest::SHA1.hexdigest("dependabot/dummy/#{dependency_name}-1.5.0")}") }
          its(:length) { is_expected.to eq(50) }
        end

        context "with a maximum length equal than sha1 length" do
          let(:max_length) { 40 }

          it { is_expected.to eq(Digest::SHA1.hexdigest("dependabot/dummy/#{dependency_name}-1.5.0")) }
          its(:length) { is_expected.to eq(40) }
        end

        context "with a maximum length shorter than sha1 length" do
          let(:max_length) { 20 }

          it { is_expected.to eq(Digest::SHA1.hexdigest("dependabot/dummy/#{dependency_name}-1.5.0")[0...20]) }
          its(:length) { is_expected.to eq(20) }
        end
      end
    end

    context "with multiple dependencies" do
      let(:dependencies) { [dependency, dep2] }
      let(:dep2) do
        Dependabot::Dependency.new(
          name: "statesman",
          version: "1.5.0",
          previous_version: "1.4.0",
          package_manager: "dummy",
          requirements: [{
            file: "Gemfile",
            requirement: "~> 1.5.0",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "Gemfile",
            requirement: "~> 1.4.0",
            groups: [],
            source: nil
          }]
        )
      end

      it { is_expected.to eq("dependabot/dummy/multi-fc93691fd4") }

      context "when dealing with a java property update" do
        let(:files) { [pom] }
        let(:pom) do
          Dependabot::DependencyFile.new(name: "pom.xml", content: pom_content)
        end
        let(:pom_content) do
          fixture("java", "poms", "property_pom.xml")
            .gsub("4.3.12.RELEASE", "23.6-jre")
        end
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "org.springframework:spring-beans",
              version: "23.6-jre",
              previous_version: "4.3.12.RELEASE",
              requirements: [{
                file: "pom.xml",
                requirement: "23.6-jre",
                groups: [],
                source: nil,
                metadata: { property_name: "springframework.version" }
              }],
              previous_requirements: [{
                file: "pom.xml",
                requirement: "4.3.12.RELEASE",
                groups: [],
                source: nil,
                metadata: { property_name: "springframework.version" }
              }],
              package_manager: "maven"
            ),
            Dependabot::Dependency.new(
              name: "org.springframework:spring-context",
              version: "23.6-jre",
              previous_version: "4.3.12.RELEASE",
              requirements: [{
                file: "pom.xml",
                requirement: "23.6-jre",
                groups: [],
                source: nil,
                metadata: { property_name: "springframework.version" }
              }],
              previous_requirements: [{
                file: "pom.xml",
                requirement: "4.3.12.RELEASE",
                groups: [],
                source: nil,
                metadata: { property_name: "springframework.version" }
              }],
              package_manager: "maven"
            )
          ]
        end

        it do
          expect(new_branch_name).to eq("dependabot/maven/springframework.version-23.6-jre")
        end
      end

      context "when dealing with a dependency set update" do
        let(:dependencies) { [dependency, dep2] }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "my.group:business",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "gradle",
            requirements: [{
              file: "Gemfile",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil,
              metadata: {
                dependency_set: { group: "my.group", version: "1.4.0" }
              }
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil,
              metadata: {
                dependency_set: { group: "my.group", version: "1.4.0" }
              }
            }]
          )
        end
        let(:dep2) do
          Dependabot::Dependency.new(
            name: "my.group:statesman",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "gradle",
            requirements: [{
              file: "Gemfile",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil,
              metadata: {
                dependency_set: { group: "my.group", version: "1.4.0" }
              }
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil,
              metadata: {
                dependency_set: { group: "my.group", version: "1.4.0" }
              }
            }]
          )
        end

        it { is_expected.to eq("dependabot/gradle/my.group-1.5.0") }
      end
    end

    context "with a removed transitive dependency" do
      let(:dependencies) { [removed_dep, parent_dep] }
      let(:removed_dep) do
        Dependabot::Dependency.new(
          name: "business",
          version: nil,
          previous_version: "1.4.0",
          package_manager: "dummy",
          requirements: [],
          previous_requirements: [],
          removed: true
        )
      end
      let(:parent_dep) do
        Dependabot::Dependency.new(
          name: "statesman",
          version: "1.5.0",
          previous_version: "1.4.0",
          package_manager: "dummy",
          requirements: [{
            file: "Gemfile",
            requirement: "~> 1.5.0",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "Gemfile",
            requirement: "~> 1.4.0",
            groups: [],
            source: nil
          }]
        )
      end

      it { is_expected.to eq("dependabot/dummy/multi-068ffedafd") }
    end

    context "with a : in the name" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "com.google.guava:guava",
          version: "23.6-jre",
          previous_version: "23.3-jre",
          package_manager: "java",
          requirements: [{
            file: "pom.xml",
            requirement: "23.6-jre",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "pom.xml",
            requirement: "23.3-jre",
            groups: [],
            source: nil
          }]
        )
      end

      it "replaces the colon with a hyphen" do
        expect(new_branch_name)
          .to eq("dependabot/java/com.google.guava-guava-23.6-jre")
      end
    end

    context "with an @ in the name" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@storybook/addon-knobs",
          version: "5.1.9",
          previous_version: "5.0.11",
          package_manager: "npm_and_yarn",
          requirements: []
        )
      end

      it "strips @ character" do
        expect(new_branch_name)
          .to eq("dependabot/npm_and_yarn/storybook/addon-knobs-5.1.9")
      end
    end

    context "with square brackets in the name" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "werkzeug[watchdog]",
          version: "0.16.0",
          previous_version: "0.15.0",
          package_manager: "pip",
          requirements: []
        )
      end

      it "replaces the brackets with hyphens" do
        expect(new_branch_name)
          .to eq("dependabot/pip/werkzeug-watchdog--0.16.0")
      end
    end

    context "with an invalid control character name" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "werk\1zeug",
          version: "0.16.0",
          previous_version: "0.15.0",
          package_manager: "pip",
          requirements: []
        )
      end

      it "strips the invalid character" do
        expect(new_branch_name)
          .to eq("dependabot/pip/werkzeug-0.16.0")
      end
    end

    context "with a requirement only" do
      let(:previous_version) { nil }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: requirement_string,
          groups: [],
          source: nil
        }]
      end
      let(:requirement_string) { "~> 1.5.0" }

      it { is_expected.to eq("dependabot/dummy/business-tw-1.5.0") }

      context "when there is a trailing dot" do
        let(:requirement_string) { "^7." }

        it { is_expected.to eq("dependabot/dummy/business-tw-7") }
      end
    end

    context "with SHA-1 versions" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: new_version,
          previous_version: previous_version,
          package_manager: "dummy",
          requirements: [{
            file: "Gemfile",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/gocardless/business",
              ref: new_ref
            }
          }],
          previous_requirements: [{
            file: "Gemfile",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/gocardless/business",
              ref: old_ref
            }
          }]
        )
      end
      let(:new_version) { "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2" }
      let(:previous_version) { "2468a02a6230e59ed1232d95d1ad3ef157195b03" }
      let(:new_ref) { nil }
      let(:old_ref) { nil }

      it "truncates the version" do
        expect(new_branch_name).to eq("dependabot/dummy/business-cff701b")
      end

      context "when there is a ref change" do
        let(:new_ref) { "v1.1.0" }
        let(:old_ref) { "v1.0.0" }

        it "includes the ref rather than the commit" do
          expect(new_branch_name).to eq("dependabot/dummy/business-v1.1.0")
        end

        context "when dealing with a library" do
          let(:new_version) { nil }
          let(:previous_version) { nil }

          it "includes the ref rather than the commit" do
            expect(new_branch_name).to eq("dependabot/dummy/business-v1.1.0")
          end
        end
      end
    end

    context "with a Docker digest update" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ubuntu",
          version: "17.10",
          previous_version: previous_version,
          package_manager: "docker",
          requirements: [{
            file: "Dockerfile",
            requirement: nil,
            groups: [],
            source: {
              type: "digest",
              digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8d" \
                      "fc38288cf73aa07485005"
            }
          }],
          previous_requirements: [{
            file: "Dockerfile",
            requirement: nil,
            groups: [],
            source: {
              type: "digest",
              digest: "sha256:2167a21baaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
                      "aaaaaaaaaaaaaaaaaaaaa"
            }
          }]
        )
      end
      let(:previous_version) { "17.10" }

      it "truncates the version" do
        expect(new_branch_name).to eq("dependabot/docker/ubuntu-1830542")
      end

      context "when there is a tag change" do
        let(:previous_version) { "17.04" }

        it "includes the tag rather than the SHA" do
          expect(new_branch_name).to eq("dependabot/docker/ubuntu-17.10")
        end
      end
    end

    context "with multiple previous source refs" do
      let(:dependency_name) { "actions/checkout" }
      let(:dependency_version) { "aabbfeb2ce60b5bd82389903509092c4648a9713" }
      let(:previous_version) { nil }
      let(:requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@v2.1.0" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.2.0",
            branch: nil
          }
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@master" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.2.0",
            branch: nil
          }
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@v2.1.0" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.1.0",
            branch: nil
          }
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@master" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "master",
            branch: nil
          }
        }]
      end

      it "includes the new ref" do
        expect(new_branch_name).to eq(
          "dependabot/dummy/actions/checkout-v2.2.0"
        )
      end
    end

    context "when going from a git ref to a version requirement" do
      let(:dependency_name) { "business" }
      let(:dependency_version) { "v2.0.0" }
      let(:previous_version) { nil }
      let(:requirements) do
        [{
          requirement: "~> 2.0.0",
          groups: [],
          file: "Gemfile",
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: "Gemfile",
          source: {
            type: "git",
            url: "https://github.com/gocardless/business",
            ref: "v1.2.0",
            branch: nil
          }
        }]
      end

      it "includes the new version" do
        expect(new_branch_name).to eq(
          "dependabot/dummy/business-tw-2.0.0"
        )
      end
    end

    context "when going from a version requirement to a git ref" do
      let(:dependency_name) { "business" }
      let(:dependency_version) { "aabbfeb2ce60b5bd82389903509092c4648a9713" }
      let(:previous_version) { "v2.0.0" }
      let(:requirements) do
        [{
          requirement: nil,
          groups: [],
          file: "Gemfile",
          source: {
            type: "git",
            url: "https://github.com/gocardless/business",
            ref: "v2.2.0",
            branch: nil
          }
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: "~> 2.0.0",
          groups: [],
          file: "Gemfile",
          source: nil
        }]
      end

      it "includes the new ref" do
        expect(new_branch_name).to eq(
          "dependabot/dummy/business-v2.2.0"
        )
      end
    end

    context "when no dependency group is present" do
      it "delegates to a solo strategy" do
        strategy = instance_double(described_class::SoloStrategy)
        allow(described_class::SoloStrategy).to receive(:new).and_return(strategy)

        branch_namer =
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            dependency_group: nil
          )

        expect(strategy).to receive(:new_branch_name).and_return("dependabot/dummy/business-1.1.0")

        branch_namer.new_branch_name
      end
    end

    context "when a dependency group is present" do
      it "delegates to a dependency group strategy" do
        strategy = instance_double(described_class::DependencyGroupStrategy)
        allow(described_class::DependencyGroupStrategy).to receive(:new).and_return(strategy)

        dependency_group = double("DependencyGroup", name: "my_dependency_group")
        branch_namer =
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            dependency_group: dependency_group
          )

        expect(strategy).to receive(:new_branch_name).and_return("dependabot/dummy/business-1.1.0")

        branch_namer.new_branch_name
      end
    end

    context "when a multi-ecosystem is present" do
      it "delegates to a multi-ecosystem strategy" do
        strategy = instance_double(described_class::MultiEcosystemStrategy)
        allow(described_class::MultiEcosystemStrategy).to receive(:new).and_return(strategy)

        branch_namer =
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            multi_ecosystem_name: "multi_ecosystem"
          )

        expect(strategy).to receive(:new_branch_name).and_return("dependabot/multi_ecosystem")

        expect(branch_namer.new_branch_name).to eq("dependabot/multi_ecosystem")
      end
    end

    context "with a word separator" do
      let(:namer) do
        described_class.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch,
          word_separator: "-"
        )
      end

      context "when the package manager has underscores" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "lodash",
            version: "4.17.21",
            previous_version: "4.17.20",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^4.17.21",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^4.17.20",
              groups: [],
              source: nil
            }]
          )
        end

        it "replaces underscores with the word separator" do
          expect(namer.new_branch_name)
            .to eq("dependabot/npm-and-yarn/lodash-4.17.21")
        end
      end

      context "when the dependency name has underscores" do
        let(:dependency_name) { "my_gem" }

        it "replaces underscores in dependency names too" do
          expect(namer.new_branch_name)
            .to eq("dependabot/dummy/my-gem-1.5.0")
        end
      end

      context "when word_separator is nil (default)" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch
          )
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "lodash",
            version: "4.17.21",
            previous_version: "4.17.20",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^4.17.21",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^4.17.20",
              groups: [],
              source: nil
            }]
          )
        end

        it "preserves underscores" do
          expect(namer.new_branch_name)
            .to eq("dependabot/npm_and_yarn/lodash-4.17.21")
        end
      end

      context "when combined with a custom separator" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            separator: "-",
            word_separator: "-"
          )
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "lodash",
            version: "4.17.21",
            previous_version: "4.17.20",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^4.17.21",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^4.17.20",
              groups: [],
              source: nil
            }]
          )
        end

        it "replaces both slashes and underscores" do
          expect(namer.new_branch_name)
            .to eq("dependabot-npm-and-yarn-lodash-4.17.21")
        end
      end
    end

    context "with branch_name_case set to lower" do
      let(:namer) do
        described_class.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch,
          branch_name_case: "lower"
        )
      end

      context "when the dependency name has uppercase characters" do
        let(:dependency_name) { "MyPackage" }

        it "downcases content after the prefix" do
          expect(namer.new_branch_name)
            .to eq("dependabot/dummy/mypackage-1.5.0")
        end
      end

      context "when the prefix has uppercase" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            prefix: "MyProject",
            branch_name_case: "lower"
          )
        end
        let(:dependency_name) { "MyPackage" }

        it "preserves prefix casing but downcases content" do
          expect(namer.new_branch_name)
            .to eq("MyProject/dummy/mypackage-1.5.0")
        end
      end
    end

    context "with branch_name_case set to upper" do
      let(:namer) do
        described_class.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch,
          branch_name_case: "upper"
        )
      end

      context "when the dependency name has lowercase characters" do
        let(:dependency_name) { "business" }

        it "upcases content after the prefix" do
          expect(namer.new_branch_name)
            .to eq("dependabot/DUMMY/BUSINESS-1.5.0")
        end
      end

      context "when the prefix has lowercase" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            prefix: "myPrefix",
            branch_name_case: "upper"
          )
        end
        let(:dependency_name) { "business" }

        it "preserves prefix casing but upcases content" do
          expect(namer.new_branch_name)
            .to eq("myPrefix/DUMMY/BUSINESS-1.5.0")
        end
      end
    end

    context "with branch_name_case nil (default)" do
      let(:dependency_name) { "MyPackage" }

      let(:namer) do
        described_class.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch
        )
      end

      it "preserves original casing" do
        expect(namer.new_branch_name)
          .to eq("dependabot/dummy/MyPackage-1.5.0")
      end
    end

    context "with word_separator, branch_name_case, and custom separator combined" do
      let(:namer) do
        described_class.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch,
          separator: "-",
          word_separator: "-",
          branch_name_case: "lower"
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "MyPackage",
          version: "4.17.21",
          previous_version: "4.17.20",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "^4.17.21",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "package.json",
            requirement: "^4.17.20",
            groups: [],
            source: nil
          }]
        )
      end

      it "applies all transformations (ACR-compliant)" do
        expect(namer.new_branch_name)
          .to eq("dependabot-npm-and-yarn-mypackage-4.17.21")
      end

      context "with a custom prefix" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            separator: "-",
            word_separator: "-",
            branch_name_case: "lower",
            prefix: "MyProject-Deps"
          )
        end

        it "preserves the prefix as-is" do
          expect(namer.new_branch_name)
            .to eq("MyProject-Deps-npm-and-yarn-mypackage-4.17.21")
        end
      end

      context "with max_length truncation" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            separator: "-",
            word_separator: "-",
            branch_name_case: "lower",
            max_length: 30
          )
        end

        it "truncates with SHA after applying transformations" do
          branch_name = namer.new_branch_name
          expect(branch_name.length).to eq(30)
        end
      end
    end

    context "with template" do
      context "for solo strategy" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            template: "{prefix}/{package_manager}/{dependency}-{version}"
          )
        end

        it "renders the template with placeholder values" do
          expect(namer.new_branch_name).to eq("dependabot/dummy/business-1.5.0")
        end
      end

      context "for solo strategy with custom prefix" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            prefix: "deps",
            template: "{prefix}/{package_manager}/{dependency}-{version}"
          )
        end

        it "uses the custom prefix in the template" do
          expect(namer.new_branch_name).to eq("deps/dummy/business-1.5.0")
        end
      end

      context "for solo strategy with separator post-processing" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            separator: "-",
            template: "{prefix}/{package_manager}/{dependency}-{version}"
          )
        end

        it "replaces slashes with the configured separator" do
          expect(namer.new_branch_name).to eq("dependabot-dummy-business-1.5.0")
        end
      end

      context "for solo strategy with word_separator and case" do
        let(:dependency_name) { "my_package" }

        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            word_separator: "-",
            branch_name_case: "lower",
            template: "{prefix}/{package_manager}/{dependency}-{version}"
          )
        end

        it "applies word_separator and case after template rendering" do
          expect(namer.new_branch_name).to eq("dependabot/dummy/my-package-1.5.0")
        end
      end

      context "for solo strategy with target_branch" do
        let(:target_branch) { "develop" }

        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            template: "{prefix}/{target_branch}/{dependency}-{version}"
          )
        end

        it "includes the target branch" do
          expect(namer.new_branch_name).to eq("dependabot/develop/business-1.5.0")
        end
      end

      context "for solo strategy with directory" do
        let(:gemfile) do
          Dependabot::DependencyFile.new(
            name: "Gemfile",
            content: fixture("ruby", "gemfiles", "Gemfile"),
            directory: "/backend"
          )
        end

        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            template: "{prefix}/{package_manager}/{directory}/{dependency}-{version}"
          )
        end

        it "sanitizes directory (strips leading slash)" do
          expect(namer.new_branch_name).to eq("dependabot/dummy/backend/business-1.5.0")
        end
      end

      context "for solo strategy with root directory" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            template: "{prefix}/{package_manager}/{directory}/{dependency}-{version}"
          )
        end

        it "uses 'root' for the root directory" do
          expect(namer.new_branch_name).to eq("dependabot/dummy/root/business-1.5.0")
        end
      end

      context "for group strategy" do
        let(:dependency_group) { double("DependencyGroup", name: "frontend-deps") }

        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            dependency_group: dependency_group,
            template: "{prefix}/{package_manager}/{group_name}"
          )
        end

        it "renders template and auto-appends digest" do
          branch_name = namer.new_branch_name
          expect(branch_name).to match(%r{^dependabot/dummy/frontend-deps-[a-f0-9]{10}$})
        end
      end

      context "for group strategy with separator" do
        let(:dependency_group) { double("DependencyGroup", name: "frontend-deps") }

        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            dependency_group: dependency_group,
            separator: "-",
            template: "{prefix}/{package_manager}/{group_name}"
          )
        end

        it "applies separator after template rendering" do
          branch_name = namer.new_branch_name
          expect(branch_name).to match(/^dependabot-dummy-frontend-deps-[a-f0-9]{10}$/)
        end
      end

      context "for multi_ecosystem strategy" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            multi_ecosystem_name: "all-security",
            template: "{prefix}/security/{group_name}"
          )
        end

        it "renders template and auto-appends digest" do
          branch_name = namer.new_branch_name
          expect(branch_name).to match(%r{^dependabot/security/all-security-[a-f0-9]{10}$})
        end
      end

      context "for solo strategy with max_length" do
        let(:namer) do
          described_class.new(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            max_length: 30,
            template: "{prefix}/{package_manager}/{dependency}-{version}"
          )
        end

        it "truncates to max_length" do
          expect(namer.new_branch_name.length).to eq(30)
        end
      end
    end
  end
end
