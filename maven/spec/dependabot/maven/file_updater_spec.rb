# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/maven/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Maven::FileUpdater do
  let(:dependency_groups) { ["test"] }
  let(:mockk_dependency) do
    Dependabot::Dependency.new(
      name: "io.mockk:mockk",
      version: "1.10.0",
      requirements: [{
        file: "pom.xml",
        requirement: "1.10.0",
        groups: [],
        source: nil,
        metadata: {
          packaging_type: "jar",
          classifier: "sources"
        }
      }],
      previous_requirements: [{
        file: "pom.xml",
        requirement: "1.0.0",
        groups: [],
        source: nil,
        metadata: {
          packaging_type: "jar",
          classifier: "sources"
        }
      }],
      package_manager: "maven"
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "org.apache.httpcomponents:httpclient",
      version: "4.6.1",
      requirements: [{
        file: "pom.xml",
        requirement: "4.6.1",
        groups: dependency_groups,
        source: nil,
        metadata: { packaging_type: "jar" }
      }],
      previous_requirements: [{
        file: "pom.xml",
        requirement: "4.5.3",
        groups: dependency_groups,
        source: nil,
        metadata: { packaging_type: "jar" }
      }],
      package_manager: "maven"
    )
  end
  let(:pom_body) { fixture("poms", "basic_pom.xml") }
  let(:pom) do
    Dependabot::DependencyFile.new(content: pom_body, name: "pom.xml")
  end
  let(:dependencies) { [dependency] }
  let(:dependency_files) { [pom] }
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_files_regex" do
    subject(:updated_files_regex) { described_class.updated_files_regex }

    it "is not empty" do
      expect(updated_files_regex).not_to be_empty
    end

    context "when files match the regex patterns" do
      it "returns true for files that should be updated" do
        matching_files = [
          "pom.xml",
          "subproject/pom.xml",
          "extensions.xml",
          "subproject/extensions.xml",
          "somefile.xml",
          "subproject/somefile.xml",
          "configs/pom.xml",
          "configs/somefile.xml"
        ]

        matching_files.each do |file_name|
          expect(updated_files_regex).to(be_any { |regex| file_name.match?(regex) })
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json"
        ]

        non_matching_files.each do |file_name|
          expect(updated_files_regex).not_to(be_any { |regex| file_name.match?(regex) })
        end
      end
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated pom file" do
      subject(:updated_pom_file) do
        updated_files.find { |f| f.name == "pom.xml" }
      end

      its(:content) { is_expected.to include("<version>4.6.1</version>") }
      its(:content) { is_expected.to include("<version>23.3-jre</version>") }

      it "doesn't update the formatting of the POM" do
        expect(updated_pom_file.content)
          .to include(%(<project xmlns="http://maven.apache.org/POM/4.0.0"\n))
      end

      context "when handling dependencies with classifiers" do
        let(:dependencies) { [dependency, mockk_dependency] }

        its(:content) { is_expected.to include("<version>1.10.0</version>") }
      end

      context "with rogue whitespace" do
        let(:pom_body) { fixture("poms", "whitespace.xml") }
        let(:dependency_groups) { [] }

        its(:content) { is_expected.to include("<version> 4.6.1 </version>") }
      end

      context "with a comment on the version" do
        let(:pom_body) { fixture("poms", "version_with_comment.xml") }

        its(:content) do
          is_expected.to include("<version>4.6.1<!--updateme--></version>")
        end
      end

      context "when the requirement is a hard requirement" do
        let(:pom_body) { fixture("poms", "hard_requirement_pom.xml") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.apache.httpcomponents:httpclient",
            version: "4.6.1",
            requirements: [{
              file: "pom.xml",
              requirement: "[4.6.1]",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }],
            previous_requirements: [{
              file: "pom.xml",
              requirement: "[4.5.3]",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }],
            package_manager: "maven"
          )
        end

        its(:content) { is_expected.to include "<version>[4.6.1]</version>" }
        its(:content) { is_expected.to include "<version>[23.3-jre]</version>" }
      end

      context "with a plugin dependency using the default groupId" do
        let(:pom_body) do
          fixture("poms", "plugin_dependencies_missing_group_id.xml")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.apache.maven.plugins:spring-boot-maven-plugin",
            version: "1.6.0.RELEASE",
            requirements: [{
              file: "pom.xml",
              requirement: "1.6.0.RELEASE",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }],
            previous_requirements: [{
              file: "pom.xml",
              requirement: "1.5.8.RELEASE",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }],
            package_manager: "maven"
          )
        end

        its(:content) do
          is_expected.to include("<version>1.6.0.RELEASE</version>")
        end

        its(:content) { is_expected.to include("<version>0.7.9</version>") }
      end

      context "with a repeated dependency" do
        let(:pom_body) { fixture("poms", "repeated_pom.xml") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.apache.maven.plugins:maven-javadoc-plugin",
            version: "3.0.0-M2",
            requirements: [{
              file: "pom.xml",
              requirement: "3.0.0-M2",
              groups: [],
              source: nil,
              metadata: { property_name: "maven-javadoc-plugin.version" }
            }, {
              file: "pom.xml",
              requirement: "3.0.0-M2",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }],
            previous_requirements: [{
              file: "pom.xml",
              requirement: "3.0.0-M1",
              groups: [],
              source: nil,
              metadata: { property_name: "maven-javadoc-plugin.version" }
            }, {
              file: "pom.xml",
              requirement: "2.10.4",
              groups: [],
              source: nil,
              metadata: { packaging_type: "jar" }
            }],
            package_manager: "maven"
          )
        end

        its(:content) { is_expected.to include "plugin.version>3.0.0-M2" }
        its(:content) { is_expected.to include "<version>3.0.0-M2</version>" }

        context "when both versions are hard-coded, and one is up-to-date" do
          let(:pom_body) do
            fixture("poms", "repeated_no_property_pom.xml")
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "org.apache.maven.plugins:maven-javadoc-plugin",
              version: "3.0.0-M2",
              requirements: [{
                file: "pom.xml",
                requirement: "3.0.0-M2",
                groups: [],
                source: { type: "maven_repo", url: "https://some.repo.com" },
                metadata: { packaging_type: "jar" }
              }, {
                file: "pom.xml",
                requirement: "3.0.0-M2",
                groups: [],
                source: { type: "maven_repo", url: "https://some.repo.com" },
                metadata: { packaging_type: "jar" }
              }],
              previous_requirements: [{
                file: "pom.xml",
                requirement: "3.0.0-M2",
                groups: [],
                source: nil,
                metadata: { packaging_type: "jar" }
              }, {
                file: "pom.xml",
                requirement: "2.10.4",
                groups: [],
                source: nil,
                metadata: { packaging_type: "jar" }
              }],
              package_manager: "maven"
            )
          end

          its(:content) { is_expected.to include "<version>3.0.0-M2</version>" }
          its(:content) { is_expected.not_to include "<version>2.10.4</version>" }
        end

        context "when both versions are hard-coded, and are identical" do
          let(:pom_body) { fixture("poms", "repeated_pom_identical.xml") }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "org.apache.maven.plugins:maven-javadoc-plugin",
              version: "3.0.0-M2",
              requirements: [{
                file: "pom.xml",
                requirement: "3.0.0-M2",
                groups: [],
                source: { type: "maven_repo", url: "https://some.repo.com" },
                metadata: { packaging_type: "jar" }
              }],
              previous_requirements: [{
                file: "pom.xml",
                requirement: "2.10.4",
                groups: [],
                source: nil,
                metadata: { packaging_type: "jar" }
              }],
              package_manager: "maven"
            )
          end

          its(:content) { is_expected.to include "<version>3.0.0-M2</version>" }
          its(:content) { is_expected.not_to include "<version>2.10.4</version>" }

          context "when they have different scopes" do
            let(:pom_body) { fixture("poms", "repeated_dev_and_prod.xml") }
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "org.apache.maven.plugins:maven-javadoc-plugin",
                version: "3.0.0-M2",
                requirements: [{
                  file: "pom.xml",
                  requirement: "3.0.0-M2",
                  groups: ["test"],
                  source: { type: "maven_repo", url: "https://some.repo.com" },
                  metadata: { packaging_type: "jar" }
                }, {
                  file: "pom.xml",
                  requirement: "3.0.0-M2",
                  groups: [],
                  source: { type: "maven_repo", url: "https://some.repo.com" },
                  metadata: { packaging_type: "jar" }
                }],
                previous_requirements: [{
                  file: "pom.xml",
                  requirement: "2.10.4",
                  groups: ["test"],
                  source: nil,
                  metadata: { packaging_type: "jar" }
                }, {
                  file: "pom.xml",
                  requirement: "2.10.4",
                  groups: [],
                  source: nil,
                  metadata: { packaging_type: "jar" }
                }],
                package_manager: "maven"
              )
            end

            its(:content) { is_expected.to include "<version>3.0.0-M2</versio" }
            its(:content) { is_expected.not_to include "<version>2.10.4</vers" }
          end
        end
      end

      context "with multiple dependencies to be updated" do
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "org.apache.httpcomponents:httpclient",
              version: "4.6.1",
              requirements: [{
                file: "pom.xml",
                requirement: "4.6.1",
                groups: ["test"],
                source: nil,
                metadata: { packaging_type: "jar" }
              }],
              previous_requirements: [{
                file: "pom.xml",
                requirement: "4.5.3",
                groups: ["test"],
                source: nil,
                metadata: { packaging_type: "jar" }
              }],
              package_manager: "maven"
            ),
            Dependabot::Dependency.new(
              name: "com.google.guava:guava",
              version: "23.6-jre",
              requirements: [{
                file: "pom.xml",
                requirement: "23.6-jre",
                groups: [],
                source: nil,
                metadata: { packaging_type: "jar" }
              }],
              previous_requirements: [{
                file: "pom.xml",
                requirement: "23.3-jre",
                groups: [],
                source: nil,
                metadata: { packaging_type: "jar" }
              }],
              package_manager: "maven"
            )
          ]
        end

        its(:content) { is_expected.to include "<version>4.6.1</version>" }
        its(:content) { is_expected.to include "<version>23.6-jre</version>" }
      end

      context "when there is a pom with dependency version defined by a property" do
        let(:pom) do
          Dependabot::DependencyFile.new(
            content: pom_body,
            name: "pom.xml",
            directory: "/subdirectory"
          )
        end
        let(:pom_body) { fixture("poms", "property_pom.xml") }
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "org.springframework:spring-context",
              version: "5.0.0.RELEASE",
              requirements: [{
                file: "pom.xml",
                requirement: "5.0.0.RELEASE",
                groups: [],
                source: nil,
                metadata: {
                  property_name: "springframework.version",
                  packaging_type: "jar"
                }
              }],
              previous_requirements: [{
                file: "pom.xml",
                requirement: "4.3.12.RELEASE.1",
                groups: [],
                source: nil,
                metadata: {
                  property_name: "springframework.version",
                  packaging_type: "jar"
                }
              }],
              package_manager: "maven"
            ),
            Dependabot::Dependency.new(
              name: "org.springframework:spring-beans",
              version: "5.0.0.RELEASE",
              requirements: [{
                file: "pom.xml",
                requirement: "5.0.0.RELEASE",
                groups: [],
                source: nil,
                metadata: {
                  property_name: "springframework.version",
                  packaging_type: "jar"
                }
              }],
              previous_requirements: [{
                file: "pom.xml",
                requirement: "4.3.12.RELEASE",
                groups: [],
                source: nil,
                metadata: {
                  property_name: "springframework.version",
                  packaging_type: "jar"
                }
              }],
              package_manager: "maven"
            )
          ]
        end

        it "updates the version in the POM" do
          expect(updated_pom_file.content)
            .to include(
              "<springframework.version>5.0.0.RELEASE</springframework.version>"
            )
          expect(updated_pom_file.directory).to eq("/subdirectory")
        end

        it "doesn't update the formatting of the POM" do
          expect(updated_pom_file.content)
            .to include(%(<project xmlns="http://maven.apache.org/POM/4.0.0"\n))
        end

        context "with an attribute" do
          let(:pom_body) do
            fixture("poms", "property_pom_single_attribute.xml")
          end
          let(:dependencies) do
            [
              Dependabot::Dependency.new(
                name: "org.springframework:spring-beans",
                version: "5.0.0.RELEASE",
                requirements: [{
                  file: "pom.xml",
                  requirement: "5.0.0.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: {
                    property_name: "springframework.version",
                    packaging_type: "jar"
                  }
                }],
                previous_requirements: [{
                  file: "pom.xml",
                  requirement: "4.3.12.RELEASE.1",
                  groups: [],
                  source: nil,
                  metadata: {
                    property_name: "springframework.version",
                    packaging_type: "jar"
                  }
                }],
                package_manager: "maven"
              )
            ]
          end

          it "updates the version in the POM" do
            expect(updated_pom_file.content)
              .to include("<springframework.version attribute=\"value\">5.0.0.")
            expect(updated_pom_file.content)
              .to include("<version>${springframework.version}</version>")
          end
        end

        context "with a suffix" do
          let(:pom_body) do
            fixture("poms", "property_pom_single_suffix.xml")
          end
          let(:dependencies) do
            [
              Dependabot::Dependency.new(
                name: "org.springframework:spring-beans",
                version: "5.0.0.RELEASE",
                requirements: [{
                  file: "pom.xml",
                  requirement: "5.0.0.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: {
                    property_name: "springframework.version",
                    packaging_type: "jar"
                  }
                }],
                previous_requirements: [{
                  file: "pom.xml",
                  requirement: "4.3.12.RELEASE.1",
                  groups: [],
                  source: nil,
                  metadata: {
                    property_name: "springframework.version",
                    packaging_type: "jar"
                  }
                }],
                package_manager: "maven"
              )
            ]
          end

          it "updates the version in the POM" do
            expect(updated_pom_file.content)
              .to include("<springframework.version>5.0.0.RELEASE</springframe")
            expect(updated_pom_file.content)
              .to include("<version>${springframework.version}</version>")
          end
        end

        context "with a version that could accidentally replace others" do
          let(:pom_body) do
            fixture("poms", "project_version_pom.xml")
          end
          let(:dependencies) do
            [
              Dependabot::Dependency.new(
                name: "org.springframework:spring-context",
                version: "5.0.0.RELEASE",
                requirements: [{
                  file: "pom.xml",
                  requirement: "5.0.0.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: {
                    property_name: "project.version",
                    packaging_type: "jar"
                  }
                }],
                previous_requirements: [{
                  file: "pom.xml",
                  requirement: "0.0.2-RELEASE",
                  groups: [],
                  source: nil,
                  metadata: {
                    property_name: "project.version",
                    packaging_type: "jar"
                  }
                }],
                package_manager: "maven"
              ),
              Dependabot::Dependency.new(
                name: "org.springframework:spring-beans",
                version: "5.0.0.RELEASE",
                requirements: [{
                  file: "pom.xml",
                  requirement: "5.0.0.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: {
                    property_name: "project.version",
                    packaging_type: "jar"
                  }
                }],
                previous_requirements: [{
                  file: "pom.xml",
                  requirement: "0.0.2-RELEASE",
                  groups: [],
                  source: nil,
                  metadata: {
                    property_name: "project.version",
                    packaging_type: "jar"
                  }
                }],
                package_manager: "maven"
              )
            ]
          end

          it "updates the version in the POM" do
            expect(updated_pom_file.content)
              .to include("<artifactId>basic-pom</artifactId>\n  " \
                          "<version>5.0.0.RELEASE</version>")
            expect(updated_pom_file.content)
              .to include("<version>4.5.3</version>")
          end
        end
      end

      context "with double backslashes in plugin" do
        let(:pom_body) { fixture("poms", "plugin_with_double_backslashes.xml") }
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "com.diffplug.spotless:spotless-maven-plugin",
              version: "2.27.1",
              requirements: [{
                file: "pom.xml",
                requirement: "2.27.1",
                groups: [],
                source: nil,
                metadata: { packaging_type: "jar" }
              }],
              previous_requirements: [{
                file: "pom.xml",
                requirement: "2.27.0",
                groups: [],
                source: nil,
                metadata: { packaging_type: "jar" }
              }],
              package_manager: "maven"
            )
          ]
        end

        its(:content) do
          is_expected.to include("<order>java,javax,org,com,,\\\\#</order>")
        end
      end
    end

    context "when there is a updated extensions.xml file" do
      subject(:updated_extensions_file) do
        updated_files.find { |f| f.name == "extensions.xml" }
      end

      let(:dependency_files) { [pom, extensions] }
      let(:extensions) do
        Dependabot::DependencyFile.new(
          name: "extensions.xml",
          content: fixture("extensions", "extensions.xml")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "io.takari.polyglot:polyglot-yaml",
          version: "0.4.7",
          requirements: [{
            file: "extensions.xml",
            requirement: "0.4.7",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }],
          previous_requirements: [{
            file: "extensions.xml",
            requirement: "0.4.6",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }],
          package_manager: "maven"
        )
      end

      its(:content) { is_expected.to include("<version>0.4.7</version>") }
    end

    context "when updating an annotationProcessorPaths dependency" do
      subject(:updated_extensions_file) do
        updated_files.find { |f| f.name == "pom.xml" }
      end

      let(:pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "annotation_processor_paths_dependencies.xml")
        )
      end
      let(:dependency_files) { [pom] }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "com.google.errorprone:error_prone_core",
          version: "2.18.0",
          requirements: [{
            file: "pom.xml",
            requirement: "2.18.0",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }],
          previous_requirements: [{
            file: "pom.xml",
            requirement: "2.9.0",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }],
          package_manager: "maven"
        )
      end

      its(:content) { is_expected.to include("<version>2.18.0</version>") }
    end

    context "when updating a plugin artifactItem dependency" do
      subject(:updated_extensions_file) do
        updated_files.find { |f| f.name == "pom.xml" }
      end

      let(:pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "plugin_dependencies_artifactItems_pom.xml")
        )
      end
      let(:dependency_files) { [pom] }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "com.eclipsesource.minimal-json:minimal-json",
          version: "0.9.5",
          requirements: [{
            file: "pom.xml",
            requirement: "0.9.5",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }],
          previous_requirements: [{
            file: "pom.xml",
            requirement: "0.9.4",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }],
          package_manager: "maven"
        )
      end

      its(:content) { is_expected.to include("<version>0.9.5</version>") }
    end

    context "with a multimodule pom" do
      let(:dependency_files) do
        [
          multimodule_pom, util_pom, business_app_pom, legacy_pom, webapp_pom,
          some_spring_project_pom
        ]
      end
      let(:multimodule_pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "multimodule_pom.xml")
        )
      end
      let(:util_pom) do
        Dependabot::DependencyFile.new(
          name: "util/pom.xml",
          content: fixture("poms", "util_pom.xml")
        )
      end
      let(:business_app_pom) do
        Dependabot::DependencyFile.new(
          name: "business-app/pom.xml",
          content: fixture("poms", "business_app_pom.xml")
        )
      end
      let(:legacy_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/pom.xml",
          content: fixture("poms", "legacy_pom.xml")
        )
      end
      let(:webapp_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/webapp/pom.xml",
          content: fixture("poms", "webapp_pom.xml")
        )
      end
      let(:some_spring_project_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/some-spring-project/pom.xml",
          content: fixture("poms", "some_spring_project_pom.xml")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: dependency_version,
          requirements: dependency_requirements,
          previous_requirements: dependency_previous_requirements,
          package_manager: "maven"
        )
      end

      context "when dealing with a dependency inherited by others" do
        let(:dependency_requirements) do
          [{
            requirement: "23.6-jre",
            file: "pom.xml",
            groups: [],
            source: nil,
            metadata: {
              property_name: "guava.version",
              packaging_type: "jar"
            }
          }, {
            requirement: nil,
            file: "util/pom.xml",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            requirement: "23.0-jre",
            file: "pom.xml",
            groups: [],
            source: nil,
            metadata: {
              property_name: "guava.version",
              packaging_type: "jar"
            }
          }, {
            requirement: nil,
            file: "util/pom.xml",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }]
        end
        let(:dependency_name) { "com.google.guava:guava" }
        let(:dependency_version) { "23.6-jre" }

        it "updates the version in the POM" do
          expect(updated_files.map(&:name)).to eq(["pom.xml"])
          expect(updated_files.first.content)
            .to include("<guava.version>23.6-jre</guava.version>")
        end
      end

      context "when dealing with a dependency that uses a property from its parent" do
        let(:dependency_requirements) do
          [{
            requirement: "2.6.0",
            file: "legacy/some-spring-project/pom.xml",
            groups: [],
            source: nil,
            metadata: { property_name: "spring.version", packaging_type: "jar" }
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            requirement: "2.5.6",
            file: "legacy/some-spring-project/pom.xml",
            groups: [],
            source: nil,
            metadata: { property_name: "spring.version", packaging_type: "jar" }
          }]
        end
        let(:dependency_name) { "org.springframework:spring-aop" }
        let(:dependency_version) { "2.6.0" }

        it "updates the version in the POM" do
          expect(updated_files.map(&:name)).to eq(["pom.xml"])
          expect(updated_files.first.content)
            .to include("<spring.version>2.6.0</spring.version>")
        end
      end

      context "when dealing with a dependency that needs to be updated in another file" do
        let(:dependency_requirements) do
          [{
            requirement: "4.11",
            file: "business-app/pom.xml",
            groups: ["test"],
            source: nil,
            metadata: { packaging_type: "jar" }
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            requirement: "4.10",
            file: "business-app/pom.xml",
            groups: ["test"],
            source: nil,
            metadata: { packaging_type: "jar" }
          }]
        end
        let(:dependency_name) { "junit:junit" }
        let(:dependency_version) { "4.11" }

        it "updates the version in the POM" do
          expect(updated_files.map(&:name)).to eq(["business-app/pom.xml"])
          expect(updated_files.first.content)
            .to include("<version>4.11</version>")
        end
      end
    end

    context "with a multimodule custom named child poms" do
      let(:dependency_files) do
        [
          multimodule_custom_pom, submodule_one_pom, submodule_two_pom, submodule_three_pom
        ]
      end
      let(:multimodule_custom_pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "multimodule_custom_modules.xml")
        )
      end
      let(:submodule_one_pom) do
        Dependabot::DependencyFile.new(
          name: "submodule-one/pom.xml",
          content: fixture("poms", "multimodule_custom_modules_submodule_one_pom.xml")
        )
      end
      let(:submodule_two_pom) do
        Dependabot::DependencyFile.new(
          name: "submodule-two/notpom.xml",
          content: fixture("poms", "multimodule_custom_modules_submodule_two_pom.xml")
        )
      end
      let(:submodule_three_pom) do
        Dependabot::DependencyFile.new(
          name: "submodule-three/some-other-name.xml",
          content: fixture("poms", "multimodule_custom_modules_submodule_three_pom.xml")
        )
      end

      context "when dealing with a dependency in a normal and custom named pom" do
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "org.apache.httpcomponents:httpclient",
              version: "4.0",
              requirements: [{
                requirement: "4.5.13",
                file: "submodule-one/pom.xml",
                groups: [],
                source: nil,
                metadata: {
                  packaging_type: "jar"
                }
              }],
              previous_requirements: [{
                requirement: "4.0",
                file: "submodule-one/pom.xml",
                groups: [],
                source: nil,
                metadata: {
                  packaging_type: "jar"
                }
              }],
              package_manager: "maven"
            ),
            Dependabot::Dependency.new(
              name: "org.springframework:spring-core",
              version: "4.3.11.RELEASE",
              requirements: [{
                requirement: "5.0.0.RELEASE",
                file: "submodule-three/some-other-name.xml",
                groups: [],
                source: nil,
                metadata: {
                  packaging_type: "jar"
                }
              }],
              previous_requirements: [{
                requirement: "4.3.11.RELEASE",
                file: "submodule-three/some-other-name.xml",
                groups: [],
                source: nil,
                metadata: {
                  packaging_type: "jar"
                }
              }],
              package_manager: "maven"
            )
          ]
        end

        it "updates the version in both pom-s" do
          expect(updated_files.map(&:name)).to eq(%w(submodule-one/pom.xml submodule-three/some-other-name.xml))
          expect(updated_files.first.content)
            .to include("<version>4.5.13</version>")
          expect(updated_files.last.content)
            .to include("<version>5.0.0.RELEASE</version>")
        end
      end
    end

    context "with a remote parent" do
      let(:pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "pom_with_parent.xml")
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.springframework.boot:spring-boot-starter-parent",
          version: "2.6.1",
          requirements: [{
            file: "pom.xml",
            requirement: "2.6.1",
            groups: [],
            source: { type: "maven_repo", url: "https://repo.maven.apache.org/maven2" },
            metadata: { packaging_type: "pom" }
          }],
          previous_requirements: [{
            file: "pom.xml",
            requirement: "1.5.9.RELEASE",
            groups: [],
            source: { type: "maven_repo", url: "https://repo.maven.apache.org/maven2" },
            metadata: { packaging_type: "pom" }
          }],
          package_manager: "maven"
        )
      end

      it "updates the version of the parent in the POM" do
        expect(updated_files.first.content)
          .to include("<version>2.6.1</version>")
      end

      context "with insignificant whitespace" do
        let(:pom) do
          Dependabot::DependencyFile.new(
            name: "pom.xml",
            content: fixture("poms", "pom_with_parent_and_insignificant_whitespace.xml")
          )
        end

        it "updates the version of the parent in the POM" do
          expect(updated_files.first.content)
            .to include("<version>2.6.1</version>")
        end
      end
    end

    context "with a parent pom having own dependencies" do
      let(:dependency_files) do
        [
          pom, parent_pom
        ]
      end
      let(:pom) do
        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: fixture("poms", "inheritance_custom_named_pom.xml")
        )
      end
      let(:parent_pom) do
        Dependabot::DependencyFile.new(
          name: "parentpom.xml",
          content: fixture("poms", "inheritance_custom_named_parent_pom.xml")
        )
      end

      context "when dealing with a dependencies in a pom and its parent do" do
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "org.apache.httpcomponents:httpclient",
              version: "4.0",
              requirements: [{
                requirement: "4.5.13",
                file: "pom.xml",
                groups: [],
                source: nil,
                metadata: {
                  packaging_type: "jar"
                }
              }],
              previous_requirements: [{
                requirement: "4.0",
                file: "pom.xml",
                groups: [],
                source: nil,
                metadata: {
                  packaging_type: "jar"
                }
              }],
              package_manager: "maven"
            ),
            Dependabot::Dependency.new(
              name: "org.springframework:spring-aop",
              version: "4.0.5.RELEASE",
              requirements: [{
                requirement: "5.0.0.RELEASE",
                file: "parentpom.xml",
                groups: [],
                source: nil,
                metadata: {
                  packaging_type: "jar"
                }
              }],
              previous_requirements: [{
                requirement: "4.0.5.RELEASE",
                file: "parentpom.xml",
                groups: [],
                source: nil,
                metadata: {
                  packaging_type: "jar"
                }
              }],
              package_manager: "maven"
            )
          ]
        end

        it "updates the version in both pom and its parent" do
          expect(updated_files.map(&:name)).to eq(%w(pom.xml parentpom.xml))
          expect(updated_files.first.content)
            .to include("<version>4.5.13</version>")
          expect(updated_files.last.content)
            .to include("<version>5.0.0.RELEASE</version>")
        end
      end
    end
  end
end
