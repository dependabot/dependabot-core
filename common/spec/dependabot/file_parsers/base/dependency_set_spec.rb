# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"

RSpec.describe Dependabot::FileParsers::Base::DependencySet do
  let(:dependency_set) { described_class.new }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.3",
      requirements: [{ requirement: "1", file: "a", groups: nil, source: nil }],
      package_manager: "dummy"
    )
  end

  describe ".new" do
    context "with no argument" do
      subject { described_class.new }
      it { is_expected.to be_a(described_class) }
      its(:dependencies) { is_expected.to eq([]) }
    end

    context "with an array argument" do
      subject { described_class.new([dependency]) }

      it { is_expected.to be_a(described_class) }
      its(:dependencies) { is_expected.to eq([dependency]) }

      context "that contains non-dependency objects" do
        subject { described_class.new([dependency, :a]) }

        it "raises a helpful error" do
          expect { described_class.new(:a) }.
            to raise_error(ArgumentError) do |error|
              expect(error.message).to include("array of Dependency objects")
            end
        end
      end
    end

    context "with a non-array argument" do
      subject { described_class.new(dependency) }

      it "raises a helpful error" do
        expect { described_class.new(:a) }.
          to raise_error(ArgumentError) do |error|
            expect(error.message).to eq "must be an array of Dependency objects"
          end
      end
    end
  end

  describe "<<" do
    subject { dependency_set << dependency }

    it { is_expected.to be_a(described_class) }
    its(:dependencies) { is_expected.to eq([dependency]) }

    context "when a dependency already exists in the set" do
      before { dependency_set << existing_dependency }

      context "and is identical to the one being added" do
        let(:existing_dependency) { dependency }

        it { is_expected.to be_a(described_class) }
        its(:dependencies) { is_expected.to eq([existing_dependency]) }

        context "with a difference in name capitalisation" do
          let(:existing_dependency) do
            Dependabot::Dependency.new(
              name: "Business",
              version: "1.3",
              requirements: [{
                requirement: "1",
                file: "a",
                groups: nil,
                source: nil
              }],
              package_manager: "dummy"
            )
          end

          context "acting case-sensitively" do
            let(:dependency_set) { described_class.new(case_sensitive: true) }

            it { is_expected.to be_a(described_class) }
            its(:dependencies) do
              is_expected.to eq([existing_dependency, dependency])
            end
          end

          context "acting case-insensitively (the default)" do
            it { is_expected.to be_a(described_class) }
            its(:dependencies) { is_expected.to eq([existing_dependency]) }
          end
        end
      end

      context "and is different to the one being added" do
        let(:existing_dependency) do
          Dependabot::Dependency.new(
            name: "statesman",
            version: "1.3",
            requirements:
              [{ requirement: "1", file: "a", groups: nil, source: nil }],
            package_manager: "dummy"
          )
        end

        it { is_expected.to be_a(described_class) }
        its(:dependencies) do
          is_expected.to match_array([existing_dependency, dependency])
        end
      end

      context "and is identical, but with different requirements" do
        let(:existing_dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.3",
            requirements:
              [{ requirement: "1", file: "b", groups: nil, source: nil }],
            package_manager: "dummy"
          )
        end

        it { is_expected.to be_a(described_class) }

        it "has a single dependency with the combined requirements" do
          expect(subject.dependencies.count).to eq(1)
          expect(subject.dependencies.first.requirements).
            to match_array(
              [
                { requirement: "1", file: "a", groups: nil, source: nil },
                { requirement: "1", file: "b", groups: nil, source: nil }
              ]
            )
        end
      end

      context "and is identical, but with different subdependency_metadata" do
        let(:existing_subdependency_metadata) { [{ npm_bundled: true }] }
        let(:subdependency_metadata) { [{ npm_bundled: false }] }
        let(:existing_dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.3",
            requirements: [],
            package_manager: "dummy",
            subdependency_metadata: existing_subdependency_metadata
          )
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.3",
            requirements: [],
            package_manager: "dummy",
            subdependency_metadata: subdependency_metadata
          )
        end

        it { is_expected.to be_a(described_class) }

        it "has a single dependency with the merged subdependency_metadata" do
          expect(subject.dependencies.count).to eq(1)
          expect(subject.dependencies.first.subdependency_metadata).
            to eq([{ npm_bundled: true }, { npm_bundled: false }])
        end

        context "when existing dependency has no subdependency_metadata" do
          let(:existing_subdependency_metadata) { nil }

          it "has a single dependency with the merged subdependency_metadata" do
            expect(subject.dependencies.count).to eq(1)
            expect(subject.dependencies.first.subdependency_metadata).
              to eq([{ npm_bundled: false }])
          end
        end

        context "when dependency has no subdependency_metadata" do
          let(:subdependency_metadata) { [] }

          it "has a single dependency with the merged subdependency_metadata" do
            expect(subject.dependencies.count).to eq(1)
            expect(subject.dependencies.first.subdependency_metadata).
              to eq([{ npm_bundled: true }])
          end
        end

        context "when neither have subdependency_metadata" do
          let(:existing_subdependency_metadata) { nil }
          let(:subdependency_metadata) { [] }

          it "has a single dependency with no subdependency_metadata" do
            expect(subject.dependencies.count).to eq(1)
            expect(subject.dependencies.first.subdependency_metadata).to be_nil
          end
        end
      end
    end

    context "with a non-dependency object" do
      let(:dependency) { :a }

      it "raises a helpful error" do
        expect { dependency_set << dependency }.
          to raise_error(ArgumentError) do |error|
            expect(error.message).to eq("must be a Dependency object")
          end
      end
    end
  end

  describe "+" do
    subject { dependency_set + described_class.new([dependency]) }

    it { is_expected.to be_a(described_class) }
    its(:dependencies) { is_expected.to eq([dependency]) }

    it "delegates to << " do
      expect(dependency_set).to receive(:<<).with(dependency).and_call_original
      subject
    end

    context "with a non-dependency-set" do
      it "raises a helpful error" do
        expect { dependency_set + [dependency] }.
          to raise_error(ArgumentError) do |error|
            expect(error.message).to eq("must be a DependencySet")
          end
      end
    end
  end

  context "when multiple versions of a dependency are added" do
    let(:foo_v1) do
      Dependabot::Dependency.new(
        name: "foo",
        version: "1.0",
        requirements: [],
        package_manager: "dummy"
      )
    end

    let(:foo_v1_1) do # rubocop:disable Naming/VariableNumber
      Dependabot::Dependency.new(
        name: "foo",
        version: "1.1",
        requirements: [{
          requirement: "^1",
          file: "Dummyfile",
          groups: nil,
          source: nil
        }],
        package_manager: "dummy"
      )
    end

    let(:foo_v1_1_alt) do
      Dependabot::Dependency.new(
        name: "foo",
        version: "1.1",
        requirements: [{
          requirement: "^1",
          file: "Dummyfile.lock",
          groups: ["prod"],
          source: {
            type: "registry",
            url: "https://registry.dummy.org"
          }
        }],
        package_manager: "dummy"
      )
    end

    let(:foo_sha) do
      Dependabot::Dependency.new(
        name: "foo",
        version: "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8",
        requirements: [{
          requirement: "^1",
          file: "Dummyfile.lock",
          groups: ["prod"],
          source: {
            type: "git",
            url: "https://github.com/acme-inc/foo",
            branch: nil,
            ref: "main"
          }
        }],
        package_manager: "dummy"
      )
    end

    it "merges each into a single combined dependency" do
      dependency_set = described_class.new << foo_v1 << foo_sha << foo_v1_1

      expect(dependency_set.dependency_for_name("foo")).to eq(
        Dependabot::Dependency.new(
          name: "foo",
          version: "1.0",
          requirements: (
            foo_v1.requirements +
            foo_sha.requirements +
            foo_v1_1.requirements
          ).uniq,
          package_manager: "dummy"
        )
      )
    end

    it "maintains a sorted list of all versions added" do
      dependency_set = described_class.new << foo_v1 << foo_sha << foo_v1_1

      expect(dependency_set.all_versions_for_name("foo")).to eq([foo_v1, foo_v1_1, foo_sha])
    end

    it "preserves all versions when combined with another dependency set" do
      set_a = described_class.new << foo_v1
      set_b = described_class.new << foo_sha << foo_v1_1 << foo_v1_1_alt
      combined_set = set_a + set_b

      expect(combined_set.dependency_for_name("foo")).to eq(
        Dependabot::Dependency.new(
          name: "foo",
          version: "1.0",
          requirements: (
            foo_v1.requirements +
            foo_v1_1.requirements +
            foo_v1_1_alt.requirements +
            foo_sha.requirements
          ).uniq,
          package_manager: "dummy"
        )
      )

      expect(combined_set.all_versions_for_name("foo")).to eq([
        foo_v1,
        Dependabot::Dependency.new(
          name: "foo",
          version: "1.1",
          package_manager: "dummy",
          requirements: (foo_v1_1.requirements + foo_v1_1_alt.requirements).uniq
        ),
        foo_sha
      ])
    end

    context "and the same version is added multiple times" do
      it "combines each into the the existing version" do
        dependency_set = described_class.new << foo_v1_1 << foo_v1_1_alt << foo_sha

        expect(dependency_set.all_versions_for_name("foo")).to eq([
          Dependabot::Dependency.new(
            name: "foo",
            version: "1.1",
            package_manager: "dummy",
            requirements: (foo_v1_1.requirements + foo_v1_1_alt.requirements).uniq
          ),
          foo_sha
        ])
      end
    end
  end
end
