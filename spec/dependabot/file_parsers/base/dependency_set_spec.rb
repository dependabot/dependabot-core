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
      package_manager: "bundler"
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
        its(:dependencies) { is_expected.to eq([dependency]) }
      end

      context "and is different to the one being added" do
        let(:existing_dependency) do
          Dependabot::Dependency.new(
            name: "statesman",
            version: "1.3",
            requirements: [
              { requirement: "1", file: "a", groups: nil, source: nil }
            ],
            package_manager: "bundler"
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
            requirements: [
              { requirement: "1", file: "b", groups: nil, source: nil }
            ],
            package_manager: "bundler"
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
end
