# typed: false
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

      context "when an argument contains non-dependency objects" do
        subject { described_class.new([dependency, :a]) }

        it "raises a helpful error" do
          expect { described_class.new(:a) }
            .to raise_error(TypeError) do |error|
              expect(error.message).to include("Expected type T::Array[Dependabot::Dependency]")
            end
        end
      end
    end

    context "with a non-array argument" do
      subject { described_class.new(dependency) }

      it "raises a helpful error" do
        expect { described_class.new(:a) }
          .to raise_error(TypeError) do |error|
            expect(error.message).to include("Expected type T::Array[Dependabot::Dependency]")
          end
      end
    end
  end

  describe "<<" do
    subject(:set_of_dependencies) { dependency_set << dependency }

    it { is_expected.to be_a(described_class) }
    its(:dependencies) { is_expected.to eq([dependency]) }

    context "when a dependency already exists in the set" do
      before { dependency_set << existing_dependency }

      context "when identical to the one being added" do
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

          context "when acting case-sensitively" do
            let(:dependency_set) { described_class.new(case_sensitive: true) }

            it { is_expected.to be_a(described_class) }

            its(:dependencies) do
              is_expected.to eq([existing_dependency, dependency])
            end
          end

          context "when acting case-insensitively (the default)" do
            it { is_expected.to be_a(described_class) }
            its(:dependencies) { is_expected.to eq([existing_dependency]) }
          end
        end
      end

      context "when different to the one being added" do
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
          is_expected.to contain_exactly(existing_dependency, dependency)
        end
      end

      context "when identical but with different requirements" do
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
          expect(set_of_dependencies.dependencies.count).to eq(1)
          expect(set_of_dependencies.dependencies.first.requirements)
            .to contain_exactly(
              { requirement: "1", file: "a", groups: nil, source: nil },
              { requirement: "1", file: "b", groups: nil, source: nil }
            )
        end
      end

      context "when identical but with different subdependency_metadata" do
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
          expect(set_of_dependencies.dependencies.count).to eq(1)
          expect(set_of_dependencies.dependencies.first.subdependency_metadata)
            .to eq([{ npm_bundled: true }, { npm_bundled: false }])
        end

        context "when existing dependency has no subdependency_metadata" do
          let(:existing_subdependency_metadata) { nil }

          it "has a single dependency with the merged subdependency_metadata" do
            expect(set_of_dependencies.dependencies.count).to eq(1)
            expect(set_of_dependencies.dependencies.first.subdependency_metadata)
              .to eq([{ npm_bundled: false }])
          end
        end

        context "when dependency has no subdependency_metadata" do
          let(:subdependency_metadata) { [] }

          it "has a single dependency with the merged subdependency_metadata" do
            expect(set_of_dependencies.dependencies.count).to eq(1)
            expect(set_of_dependencies.dependencies.first.subdependency_metadata)
              .to eq([{ npm_bundled: true }])
          end
        end

        context "when neither have subdependency_metadata" do
          let(:existing_subdependency_metadata) { nil }
          let(:subdependency_metadata) { [] }

          it "has a single dependency with no subdependency_metadata" do
            expect(set_of_dependencies.dependencies.count).to eq(1)
            expect(set_of_dependencies.dependencies.first.subdependency_metadata).to be_nil
          end
        end
      end
    end

    context "with a non-dependency object" do
      let(:dependency) { :a }

      it "raises a helpful error" do
        expect { dependency_set << dependency }
          .to raise_error(TypeError) do |error|
            expect(error.message).to include("Expected type Dependabot::Dependency")
          end
      end
    end
  end

  describe "+" do
    subject(:plus_dependencies) { dependency_set + described_class.new([dependency]) }

    it { is_expected.to be_a(described_class) }
    its(:dependencies) { is_expected.to eq([dependency]) }

    it "delegates to <<" do
      expect(dependency_set).to receive(:<<).with(dependency).and_call_original
      plus_dependencies
    end

    context "with a non-dependency-set" do
      it "raises a helpful error" do
        expect { dependency_set + [dependency] }
          .to raise_error(ArgumentError) do |error|
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
          version: "1.1",
          requirements: (
            foo_v1.requirements +
            foo_sha.requirements +
            foo_v1_1.requirements
          ).uniq,
          package_manager: "dummy"
        )
      )
    end

    it "returns all versions in the order they were added by default" do
      dependency_set = described_class.new << foo_v1_1 << foo_sha << foo_v1
      expect(dependency_set.all_versions_for_name("foo")).to eq([foo_v1_1, foo_sha, foo_v1])
    end

    it "preserves all versions when combined with another dependency set" do
      set_a = described_class.new << foo_v1
      set_b = described_class.new << foo_sha << foo_v1_1 << foo_v1_1_alt
      combined_set = set_a + set_b

      expect(combined_set.dependency_for_name("foo")).to eq(
        Dependabot::Dependency.new(
          name: "foo",
          version: "1.1",
          requirements: (
            foo_v1.requirements +
            foo_sha.requirements +
            foo_v1_1.requirements +
            foo_v1_1_alt.requirements
          ).uniq,
          package_manager: "dummy"
        )
      )

      expect(combined_set.all_versions_for_name("foo")).to eq(
        [
          foo_v1,
          foo_sha,
          Dependabot::Dependency.new(
            name: "foo",
            version: "1.1",
            package_manager: "dummy",
            requirements: (foo_v1_1.requirements + foo_v1_1_alt.requirements).uniq
          )
        ]
      )
    end

    context "when the same version is added multiple times" do
      it "combines each into the the existing version" do
        dependency_set = described_class.new << foo_v1_1 << foo_v1_1_alt << foo_sha

        expect(dependency_set.all_versions_for_name("foo")).to eq(
          [
            Dependabot::Dependency.new(
              name: "foo",
              version: "1.1",
              package_manager: "dummy",
              requirements: (foo_v1_1.requirements + foo_v1_1_alt.requirements).uniq
            ),
            foo_sha
          ]
        )
      end
    end
  end

  context "when npm packages share an installation name" do
    before do
      version_class = Dependabot::Utils.version_class_for_package_manager("dummy")
      allow(Dependabot::Utils).to receive(:version_class_for_package_manager)
        .with("npm_and_yarn").and_return(version_class)
    end

    it "preserves case-insensitive version deduplication for ordinary packages" do
      records = %w(MS ms).map do |name|
        Dependabot::Dependency.new(
          name: name,
          version: "2.0.0",
          package_manager: "npm_and_yarn",
          requirements: []
        )
      end

      expect(described_class.new(records).all_versions_for_name("ms")).to eq([records.first])
    end

    [nil, "is-odd"].product(
      [["7.0.0", "2.0.0"], ["2.0.0", "7.0.0"], ["7.0.0", "7.0.0"]],
      [false, true]
    ).each do |other_target, versions, reverse|
      context "with targets is-number and #{other_target || 'ms'}, versions #{versions}, reversed: #{reverse}" do
        let(:records) do
          targets = ["is-number", other_target].zip(versions)
          targets.reverse! if reverse
          targets.map do |target, version|
            metadata = { marker: target || "ordinary" }
            metadata[:npm_package_name] = target if target
            Dependabot::Dependency.new(
              name: "ms",
              version: version,
              package_manager: "npm_and_yarn",
              requirements: [],
              metadata: metadata
            )
          end
        end
        let(:dependency_set) { described_class.new(records) }

        it "keeps every target/version and aligns the combined identity with the preferred version" do
          expected = if records.first.version == records.last.version
                       records.last
                     else
                       records.min_by { |record| Gem::Version.new(record.version) }
                     end
          combined = dependency_set.dependency_for_name("ms")

          expect(dependency_set.dependencies.length).to eq(1)
          expect(combined.version).to eq(expected.version)
          expect(combined.metadata).to eq(
            records.first.metadata.except(:npm_package_name).merge(
              expected.metadata.slice(:npm_package_name)
            )
          )
          expect(dependency_set.all_versions_for_name("ms").map { |record| [record.metadata, record.version] })
            .to eq(records.map { |record| [record.metadata, record.version] })
        end
      end
    end

    [false, true].product(["2.0.0", "7.0.0"]).each do |reverse, direct_version|
      context "with direct ordinary version #{direct_version}, reversed: #{reverse}" do
        let(:aliased) do
          Dependabot::Dependency.new(
            name: "ms",
            version: "2.0.0",
            package_manager: "npm_and_yarn",
            requirements: [],
            metadata: { npm_package_name: "is-number" }
          )
        end
        let(:ordinary) do
          Dependabot::Dependency.new(
            name: "ms",
            version: direct_version,
            package_manager: "npm_and_yarn",
            requirements: [{ requirement: ">=2.0.0", file: "package.json", groups: ["dependencies"], source: nil }]
          )
        end

        it "prefers the direct version without inheriting the alias target" do
          records = reverse ? [ordinary, aliased] : [aliased, ordinary]
          dependency_set = described_class.new(records)
          combined = dependency_set.dependency_for_name("ms")

          expect(combined.version).to eq(direct_version)
          expect(combined.metadata).not_to have_key(:npm_package_name)
          expect(combined.requirements).to eq(ordinary.requirements)
          expect(dependency_set.all_versions_for_name("ms").map { |record| [record.metadata, record.version] })
            .to eq(records.map { |record| [record.metadata, record.version] })
        end
      end
    end
  end

  it "ignores npm identity metadata for other ecosystems" do
    records = %w(is-number is-odd).map do |target|
      Dependabot::Dependency.new(
        name: "ms",
        version: "2.0.0",
        package_manager: "dummy",
        requirements: [],
        metadata: { npm_package_name: target }
      )
    end
    dependency_set = described_class.new(records)

    expect(dependency_set.all_versions_for_name("ms").length).to eq(1)
    expect(dependency_set.dependency_for_name("ms").metadata).to eq(records.first.metadata)
  end
end
