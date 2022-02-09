# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/gradle/file_parser/property_value_finder"

RSpec.describe Dependabot::Gradle::FileParser::PropertyValueFinder do
  let(:finder) { described_class.new(dependency_files: dependency_files) }

  let(:dependency_files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "single_property_build.gradle" }

  describe "#property_details" do
    subject(:property_details) do
      finder.property_details(
        property_name: property_name,
        callsite_buildfile: callsite_buildfile
      )
    end

    context "with a single buildfile" do
      context "when the property is declared in the calling buildfile" do
        let(:buildfile_fixture_name) { "single_property_build.gradle" }
        let(:property_name) { "kotlin_version" }
        let(:callsite_buildfile) { buildfile }
        its([:value]) { is_expected.to eq("1.1.4-3") }
        its([:declaration_string]) do
          is_expected.to eq("ext.kotlin_version = '1.1.4-3'")
        end
        its([:file]) { is_expected.to eq("build.gradle") }

        context "and the property name has a `project.` prefix" do
          let(:property_name) { "project.kotlin_version" }
          its([:value]) { is_expected.to eq("1.1.4-3") }
          its([:file]) { is_expected.to eq("build.gradle") }
        end

        context "and the property name has a `rootProject.` prefix" do
          let(:property_name) { "rootProject.kotlin_version" }
          its([:value]) { is_expected.to eq("1.1.4-3") }
          its([:file]) { is_expected.to eq("build.gradle") }
        end

        context "and tricky properties" do
          let(:buildfile_fixture_name) { "properties.gradle" }

          context "and the property is declared with ext.name" do
            let(:property_name) { "kotlin_version" }
            its([:value]) { is_expected.to eq("1.2.61") }
            its([:declaration_string]) do
              is_expected.to eq("ext.kotlin_version = '1.2.61'")
            end
          end

          context "and the property is declared in an ext block" do
            let(:property_name) { "buildToolsVersion" }
            its([:value]) { is_expected.to eq("27.0.3") }
            its([:declaration_string]) do
              is_expected.to eq("buildToolsVersion = '27.0.3'")
            end

            context "and the property name has already been set" do
              let(:buildfile_fixture_name) { "duplicate_property_name.gradle" }
              let(:property_name) { "spek_version" }
              its([:value]) { is_expected.to eq("2.0.6") }
              its([:declaration_string]) do
                is_expected.to eq("spek_version = '2.0.6'")
              end
            end
          end

          context "and the property is preceded by a comment" do
            # This is important because the declaration string must not include
            # whitespace that will be different to when the FileUpdater uses it
            # (i.e., before the comments are stripped out)
            let(:property_name) { "supportVersion" }
            its([:value]) { is_expected.to eq("27.1.1") }
            its([:declaration_string]) do
              is_expected.to eq("supportVersion = '27.1.1'")
            end
          end

          context "and the property is using findProperty syntax" do
            let(:property_name) { "findPropertyVersion" }
            its([:value]) { is_expected.to eq("27.1.1") }
            its([:declaration_string]) do
              is_expected.to eq("findPropertyVersion = project.findProperty('findPropertyVersion') ?: '27.1.1'")
            end
          end

          context "and the property is using hasProperty syntax" do
            let(:property_name) { "hasPropertyVersion" }
            its([:value]) { is_expected.to eq("27.1.1") }
            its([:declaration_string]) do
              # rubocop:disable Layout/LineLength
              is_expected.to eq("hasPropertyVersion = project.hasProperty('hasPropertyVersion') ? project.getProperty('hasPropertyVersion') :'27.1.1'")
              # rubocop:enable Layout/LineLength
            end
          end

          context "and the property is commented out" do
            let(:property_name) { "commentedVersion" }
            it { is_expected.to be_nil }
          end

          context "and the property is declared within a namespace" do
            let(:buildfile_fixture_name) { "properties_namespaced.gradle" }
            let(:property_name) { "versions.okhttp" }

            its([:value]) { is_expected.to eq("3.12.1") }
            its([:declaration_string]) do
              is_expected.to eq("okhttp                 : '3.12.1'")
            end
            context "and the property is using findProperty syntax" do
              let(:property_name) { "versions.findPropertyVersion" }
              its([:value]) { is_expected.to eq("1.0.0") }
              its([:declaration_string]) do
                is_expected.to eq("findPropertyVersion    : project.findProperty('findPropertyVersion') ?: '1.0.0'")
              end
            end

            context "and the property is using hasProperty syntax" do
              let(:property_name) { "versions.hasPropertyVersion" }
              its([:value]) { is_expected.to eq("1.0.0") }
              its([:declaration_string]) do
                # rubocop:disable Layout/LineLength
                is_expected.to eq("hasPropertyVersion     : project.hasProperty('hasPropertyVersion') ? project.getProperty('hasPropertyVersion') :'1.0.0'")
                # rubocop:enable Layout/LineLength
              end
            end
          end
        end
      end
    end

    context "with a script plugin" do
      let(:dependency_files) { [buildfile, script_plugin] }
      let(:buildfile_fixture_name) { "with_dependency_script.gradle" }
      let(:callsite_buildfile) { buildfile }
      let(:script_plugin) do
        Dependabot::DependencyFile.new(
          name: "gradle/dependencies.gradle",
          content: fixture("script_plugins", "dependencies.gradle")
        )
      end

      let(:property_name) { "collectionsVersion" }
      its([:value]) { is_expected.to eq("4.4") }
      its([:file]) { is_expected.to eq("gradle/dependencies.gradle") }
    end

    context "with multiple buildfiles" do
      let(:dependency_files) { [buildfile, callsite_buildfile] }
      let(:buildfile_fixture_name) { "single_property_build.gradle" }
      let(:property_name) { "kotlin_version" }
      let(:callsite_buildfile) do
        Dependabot::DependencyFile.new(
          name: "myapp/build.gradle",
          content: fixture("buildfiles", callsite_fixture_name)
        )
      end
      let(:callsite_fixture_name) { "basic_build.gradle" }

      its([:value]) { is_expected.to eq("1.1.4-3") }
      its([:file]) { is_expected.to eq("build.gradle") }

      context "and the property name has a `project.` prefix" do
        let(:property_name) { "project.kotlin_version" }
        its([:value]) { is_expected.to eq("1.1.4-3") }
        its([:file]) { is_expected.to eq("build.gradle") }
      end

      context "and the property name has a `rootProject.` prefix" do
        let(:property_name) { "rootProject.kotlin_version" }
        its([:value]) { is_expected.to eq("1.1.4-3") }
        its([:file]) { is_expected.to eq("build.gradle") }
      end

      context "with a property that only appears in the callsite buildfile" do
        let(:buildfile_fixture_name) { "basic_build.gradle" }
        let(:callsite_fixture_name) { "single_property_build.gradle" }

        context "and the property name has a `project.` prefix" do
          let(:property_name) { "project.kotlin_version" }
          its([:value]) { is_expected.to eq("1.1.4-3") }
          its([:file]) { is_expected.to eq("myapp/build.gradle") }
        end

        context "and the property name has a `rootProject.` prefix" do
          let(:property_name) { "rootProject.kotlin_version" }
          # We wouldn't normally expect this to be `nil` - it's more likely to
          # be another version specified in the root project file.
          it { is_expected.to be_nil }
        end
      end
    end

    context "with kotlin" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle.kts",
          content: fixture("buildfiles", buildfile_fixture_name)
        )
      end
      let(:buildfile_fixture_name) { "root_build.gradle.kts" }

      context "with a single buildfile" do
        context "when the property is declared in the calling buildfile" do
          let(:property_name) { "kotlinVersion" }
          let(:callsite_buildfile) { buildfile }

          its([:value]) { is_expected.to eq("1.2.61") }
          its([:declaration_string]) do
            is_expected.to eq('extra["kotlinVersion"] = "1.2.61"')
          end
          its([:file]) { is_expected.to eq("build.gradle.kts") }

          context "and the property name has a `project.` prefix" do
            let(:property_name) { "project.kotlinVersion" }
            its([:value]) { is_expected.to eq("1.2.61") }
            its([:file]) { is_expected.to eq("build.gradle.kts") }
          end

          context "and the property name has a `rootProject.` prefix" do
            let(:property_name) { "rootProject.kotlinVersion" }
            its([:value]) { is_expected.to eq("1.2.61") }
            its([:file]) { is_expected.to eq("build.gradle.kts") }
          end

          context "and tricky properties" do
            context "and the property is declared with extra[key] = value" do
              let(:property_name) { "kotlinVersion" }
              its([:value]) { is_expected.to eq("1.2.61") }
              its([:declaration_string]) do
                is_expected.to eq('extra["kotlinVersion"] = "1.2.61"')
              end
            end

            context "and the property is declared with extra.set(key, value)" do
              let(:property_name) { "javaVersion" }
              its([:value]) { is_expected.to eq("11") }
              its([:declaration_string]) do
                is_expected.to eq('extra.set("javaVersion", "11")')
              end
            end

            context "and the property is declared in an extra.apply block" do
              let(:property_name) { "buildToolsVersion" }
              its([:value]) { is_expected.to eq("27.0.3") }
              its([:declaration_string]) do
                is_expected.to eq('set("buildToolsVersion", "27.0.3")')
              end
            end

            context "and the property is preceded by a comment" do
              # This is important because the declaration string must
              # not include whitespace that will be different to when
              # the FileUpdater uses it (i.e., before the comments
              # are stripped out)
              let(:property_name) { "supportVersion" }
              its([:value]) { is_expected.to eq("27.1.1") }
              its([:declaration_string]) do
                is_expected.to eq('set("supportVersion", "27.1.1")')
              end
            end

            context "and the property is using findProperty syntax" do
              let(:property_name) { "findPropertyVersion" }
              its([:value]) { is_expected.to eq("27.1.1") }
              its([:declaration_string]) do
                is_expected.to eq('set("findPropertyVersion", project.findProperty("findPropertyVersion") ?: "27.1.1")')
              end
            end

            context "and the property is using hasProperty syntax" do
              let(:property_name) { "hasPropertyVersion" }
              its([:value]) { is_expected.to eq("27.1.1") }
              its([:declaration_string]) do
                # rubocop:disable Layout/LineLength
                is_expected.to eq('set("hasPropertyVersion", if(project.hasProperty("hasPropertyVersion")) project.getProperty("hasPropertyVersion") else "27.1.1")')
                # rubocop:enable Layout/LineLength
              end
            end

            context "and the property is commented out" do
              let(:property_name) { "commentedVersion" }
              it { is_expected.to be_nil }
            end

            context "and the property is declared within a namespace" do
              let(:buildfile_fixture_name) { "root_build.gradle.kts" }
              let(:property_name) { "versions.okhttp" }

              its([:value]) { is_expected.to eq("3.12.1") }
              its([:declaration_string]) do
                is_expected.to eq('"okhttp"                  to "3.12.1"')
              end
              context "and the property is using findProperty syntax" do
                let(:property_name) { "versions.findPropertyVersion" }
                its([:value]) { is_expected.to eq("1.0.0") }
                its([:declaration_string]) do
                  # rubocop:disable Layout/LineLength
                  is_expected.to eq('"findPropertyVersion"     to project.findProperty("findPropertyVersion") ?: "1.0.0"')
                  # rubocop:enable Layout/LineLength
                end
              end

              context "and the property is using hasProperty syntax" do
                let(:property_name) { "versions.hasPropertyVersion" }
                its([:value]) { is_expected.to eq("1.0.0") }
                its([:declaration_string]) do
                  # rubocop:disable Layout/LineLength
                  is_expected.to eq('"hasPropertyVersion"      to if(project.hasProperty("hasPropertyVersion")) project.getProperty("hasPropertyVersion") else "1.0.0"')
                  # rubocop:enable Layout/LineLength
                end
              end
            end
          end
        end
      end

      context "with a script plugin" do
        let(:dependency_files) { [buildfile, script_plugin] }
        let(:buildfile_fixture_name) { "with_dependency_script.gradle.kts" }
        let(:callsite_buildfile) { buildfile }
        let(:script_plugin) do
          Dependabot::DependencyFile.new(
            name: "gradle/dependencies.gradle.kts",
            content: fixture("script_plugins", "dependencies.gradle.kts")
          )
        end

        let(:property_name) { "collectionsVersion" }
        its([:value]) { is_expected.to eq("4.4") }
        its([:file]) { is_expected.to eq("gradle/dependencies.gradle.kts") }
      end

      context "with multiple buildfiles" do
        let(:dependency_files) { [buildfile, callsite_buildfile] }
        let(:property_name) { "kotlinVersion" }
        let(:callsite_buildfile) do
          Dependabot::DependencyFile.new(
            name: "myapp/build.gradle.kts",
            content: fixture("buildfiles", callsite_fixture_name)
          )
        end
        let(:callsite_fixture_name) { "build.gradle.kts" }

        its([:value]) { is_expected.to eq("1.2.61") }
        its([:file]) { is_expected.to eq("build.gradle.kts") }

        context "and the property name has a `project.` prefix" do
          let(:property_name) { "project.kotlinVersion" }
          its([:value]) { is_expected.to eq("1.2.61") }
          its([:file]) { is_expected.to eq("build.gradle.kts") }
        end

        context "and the property name has a `rootProject.` prefix" do
          let(:property_name) { "rootProject.kotlinVersion" }
          its([:value]) { is_expected.to eq("1.2.61") }
          its([:file]) { is_expected.to eq("build.gradle.kts") }
        end

        context "with a property that only appears in the callsite buildfile" do
          let(:buildfile_fixture_name) { "build.gradle.kts" }
          let(:callsite_fixture_name) { "root_build.gradle.kts" }

          context "and the property name has a `project.` prefix" do
            let(:property_name) { "project.kotlinVersion" }
            its([:value]) { is_expected.to eq("1.2.61") }
            its([:file]) { is_expected.to eq("myapp/build.gradle.kts") }
          end

          context "and the property name has a `rootProject.` prefix" do
            let(:property_name) { "rootProject.kotlinVersion" }
            # We wouldn't normally expect this to be `nil` - it's more likely
            # to be another version specified in the root project file.
            it { is_expected.to be_nil }
          end
        end
      end
    end
  end
end
