# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/file_updaters/java/maven"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Java::Maven do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: [{
        "type" => "git",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end
  let(:dependency_files) { [pom] }
  let(:dependencies) { [dependency] }
  let(:pom) do
    Dependabot::DependencyFile.new(content: pom_body, name: "pom.xml")
  end
  let(:pom_body) { fixture("java", "poms", "basic_pom.xml") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "org.apache.httpcomponents:httpclient",
      version: "4.6.1",
      requirements: [{
        file: "pom.xml",
        requirement: "4.6.1",
        groups: [],
        source: nil,
        metadata: nil
      }],
      previous_requirements: [{
        file: "pom.xml",
        requirement: "4.5.3",
        groups: [],
        source: nil,
        metadata: nil
      }],
      package_manager: "maven"
    )
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

      its(:content) { is_expected.to include "<version>4.6.1</version>" }
      its(:content) { is_expected.to include "<version>23.3-jre</version>" }

      it "doesn't update the formatting of the POM" do
        expect(updated_pom_file.content).
          to include(%(<project xmlns="http://maven.apache.org/POM/4.0.0"\n))
      end

      context "with rogue whitespace" do
        let(:pom_body) { fixture("java", "poms", "whitespace.xml") }
        its(:content) { is_expected.to include "<version>4.6.1</version>" }
      end

      context "when the requirement is a hard requirement" do
        let(:pom_body) { fixture("java", "poms", "hard_requirement_pom.xml") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.apache.httpcomponents:httpclient",
            version: "4.6.1",
            requirements: [
              {
                file: "pom.xml",
                requirement: "[4.6.1]",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "pom.xml",
                requirement: "[4.5.3]",
                groups: [],
                source: nil
              }
            ],
            package_manager: "maven"
          )
        end

        its(:content) { is_expected.to include "<version>[4.6.1]</version>" }
        its(:content) { is_expected.to include "<version>[23.3-jre]</version>" }
      end

      context "with a repeated dependency" do
        let(:pom_body) { fixture("java", "poms", "repeated_pom.xml") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.apache.maven.plugins:maven-javadoc-plugin",
            version: "3.0.0-M2",
            requirements: [
              {
                file: "pom.xml",
                requirement: "3.0.0-M2",
                groups: [],
                source: nil,
                metadata: { property_name: "maven-javadoc-plugin.version" }
              },
              {
                file: "pom.xml",
                requirement: "3.0.0-M2",
                groups: [],
                source: nil,
                metadata: nil
              }
            ],
            previous_requirements: [
              {
                file: "pom.xml",
                requirement: "3.0.0-M1",
                groups: [],
                source: nil,
                metadata: { property_name: "maven-javadoc-plugin.version" }
              },
              {
                file: "pom.xml",
                requirement: "2.10.4",
                groups: [],
                source: nil,
                metadata: nil
              }
            ],
            package_manager: "maven"
          )
        end

        its(:content) { is_expected.to include "plugin.version>3.0.0-M2" }
        its(:content) { is_expected.to include "<version>3.0.0-M2</version>" }

        context "when both versions are hard-coded, and one is up-to-date" do
          let(:pom_body) do
            fixture("java", "poms", "repeated_no_property_pom.xml")
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "org.apache.maven.plugins:maven-javadoc-plugin",
              version: "3.0.0-M2",
              requirements: [
                {
                  file: "pom.xml",
                  requirement: "3.0.0-M2",
                  groups: [],
                  source: { type: "maven_repo", url: "https://some.repo.com" },
                  metadata: nil
                },
                {
                  file: "pom.xml",
                  requirement: "3.0.0-M2",
                  groups: [],
                  source: { type: "maven_repo", url: "https://some.repo.com" },
                  metadata: nil
                }
              ],
              previous_requirements: [
                {
                  file: "pom.xml",
                  requirement: "3.0.0-M2",
                  groups: [],
                  source: nil,
                  metadata: nil
                },
                {
                  file: "pom.xml",
                  requirement: "2.10.4",
                  groups: [],
                  source: nil,
                  metadata: nil
                }
              ],
              package_manager: "maven"
            )
          end

          its(:content) { is_expected.to include "<version>3.0.0-M2</version>" }
          its(:content) { is_expected.to_not include "<version>2.10.4</versio" }
        end
      end

      context "with multiple dependencies to be updated" do
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "org.apache.httpcomponents:httpclient",
              version: "4.6.1",
              requirements: [
                {
                  file: "pom.xml",
                  requirement: "4.6.1",
                  groups: [],
                  source: nil
                }
              ],
              previous_requirements: [
                {
                  file: "pom.xml",
                  requirement: "4.5.3",
                  groups: [],
                  source: nil
                }
              ],
              package_manager: "maven"
            ),
            Dependabot::Dependency.new(
              name: "com.google.guava:guava",
              version: "23.6-jre",
              requirements: [
                {
                  file: "pom.xml",
                  requirement: "23.6-jre",
                  groups: [],
                  source: nil
                }
              ],
              previous_requirements: [
                {
                  file: "pom.xml",
                  requirement: "23.3-jre",
                  groups: [],
                  source: nil
                }
              ],
              package_manager: "maven"
            )
          ]
        end

        its(:content) { is_expected.to include "<version>4.6.1</version>" }
        its(:content) { is_expected.to include "<version>23.6-jre</version>" }
      end

      context "pom with dependency version defined by a property" do
        let(:pom_body) { fixture("java", "poms", "property_pom.xml") }
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "org.springframework:spring-context",
              version: "5.0.0.RELEASE",
              requirements: [
                {
                  file: "pom.xml",
                  requirement: "5.0.0.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: { property_name: "springframework.version" }
                }
              ],
              previous_requirements: [
                {
                  file: "pom.xml",
                  requirement: "4.3.12.RELEASE.1",
                  groups: [],
                  source: nil,
                  metadata: { property_name: "springframework.version" }
                }
              ],
              package_manager: "maven"
            ),
            Dependabot::Dependency.new(
              name: "org.springframework:spring-beans",
              version: "5.0.0.RELEASE",
              requirements: [
                {
                  file: "pom.xml",
                  requirement: "5.0.0.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: { property_name: "springframework.version" }
                }
              ],
              previous_requirements: [
                {
                  file: "pom.xml",
                  requirement: "4.3.12.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: { property_name: "springframework.version" }
                }
              ],
              package_manager: "maven"
            )
          ]
        end

        it "updates the version in the POM" do
          expect(updated_pom_file.content).
            to include(
              "<springframework.version>5.0.0.RELEASE</springframework.version>"
            )
        end

        it "doesn't update the formatting of the POM" do
          expect(updated_pom_file.content).
            to include(%(<project xmlns="http://maven.apache.org/POM/4.0.0"\n))
        end

        context "with a suffix" do
          let(:pom_body) do
            fixture("java", "poms", "property_pom_single_suffix.xml")
          end
          let(:dependencies) do
            [
              Dependabot::Dependency.new(
                name: "org.springframework:spring-beans",
                version: "5.0.0.RELEASE",
                requirements: [
                  {
                    file: "pom.xml",
                    requirement: "5.0.0.RELEASE",
                    groups: [],
                    source: nil,
                    metadata: { property_name: "springframework.version" }
                  }
                ],
                previous_requirements: [
                  {
                    file: "pom.xml",
                    requirement: "4.3.12.RELEASE.1",
                    groups: [],
                    source: nil,
                    metadata: { property_name: "springframework.version" }
                  }
                ],
                package_manager: "maven"
              )
            ]
          end

          it "updates the version in the POM" do
            expect(updated_pom_file.content).
              to include("<springframework.version>5.0.0.RELEASE</springframe")
            expect(updated_pom_file.content).
              to include("<version>${springframework.version}</version>")
          end
        end
      end
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
          content: fixture("java", "poms", "multimodule_pom.xml")
        )
      end
      let(:util_pom) do
        Dependabot::DependencyFile.new(
          name: "util/pom.xml",
          content: fixture("java", "poms", "util_pom.xml")
        )
      end
      let(:business_app_pom) do
        Dependabot::DependencyFile.new(
          name: "business-app/pom.xml",
          content: fixture("java", "poms", "business_app_pom.xml")
        )
      end
      let(:legacy_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/pom.xml",
          content: fixture("java", "poms", "legacy_pom.xml")
        )
      end
      let(:webapp_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/webapp/pom.xml",
          content: fixture("java", "poms", "webapp_pom.xml")
        )
      end
      let(:some_spring_project_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/some-spring-project/pom.xml",
          content: fixture("java", "poms", "some_spring_project_pom.xml")
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

      context "for a dependency inherited by others" do
        let(:dependency_requirements) do
          [
            {
              requirement: "23.6-jre",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { property_name: "guava.version" }
            },
            {
              requirement: nil,
              file: "util/pom.xml",
              groups: [],
              source: nil
            }
          ]
        end
        let(:dependency_previous_requirements) do
          [
            {
              requirement: "23.0-jre",
              file: "pom.xml",
              groups: [],
              source: nil,
              metadata: { property_name: "guava.version" }
            },
            {
              requirement: nil,
              file: "util/pom.xml",
              groups: [],
              source: nil
            }
          ]
        end
        let(:dependency_name) { "com.google.guava:guava" }
        let(:dependency_version) { "23.6-jre" }

        it "updates the version in the POM" do
          expect(updated_files.map(&:name)).to eq(["pom.xml"])
          expect(updated_files.first.content).
            to include("<guava.version>23.6-jre</guava.version>")
        end
      end

      context "for a dependency that uses a property from its parent" do
        let(:dependency_requirements) do
          [{
            requirement: "2.6.0",
            file: "legacy/some-spring-project/pom.xml",
            groups: [],
            source: nil,
            metadata: { property_name: "spring.version" }
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            requirement: "2.5.6",
            file: "legacy/some-spring-project/pom.xml",
            groups: [],
            source: nil,
            metadata: { property_name: "spring.version" }
          }]
        end
        let(:dependency_name) { "org.springframework:spring-aop" }
        let(:dependency_version) { "2.6.0" }

        it "updates the version in the POM" do
          expect(updated_files.map(&:name)).to eq(["pom.xml"])
          expect(updated_files.first.content).
            to include("<spring.version>2.6.0</spring.version>")
        end
      end

      context "for a dependency that needs to be updated in another file" do
        let(:dependency_requirements) do
          [{
            requirement: "4.11",
            file: "business-app/pom.xml",
            groups: [],
            source: nil
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            requirement: "4.10",
            file: "business-app/pom.xml",
            groups: [],
            source: nil
          }]
        end
        let(:dependency_name) { "junit:junit" }
        let(:dependency_version) { "4.11" }

        it "updates the version in the POM" do
          expect(updated_files.map(&:name)).to eq(["business-app/pom.xml"])
          expect(updated_files.first.content).
            to include("<version>4.11</version>")
        end
      end
    end
  end
end
