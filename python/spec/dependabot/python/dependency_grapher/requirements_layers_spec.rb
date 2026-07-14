# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python"
require "dependabot/python/dependency_grapher/requirements_layers"

RSpec.describe Dependabot::Python::DependencyGrapher::RequirementsLayers do
  subject(:layers) { described_class.new(dependency_files: dependency_files) }

  def file(name, content = "")
    Dependabot::DependencyFile.new(name: name, content: content, directory: "/")
  end

  describe ".manifest_txt_filename?" do
    [
      "requirements.txt",
      "requirements.prod.txt",
      "requirements/production.txt",
      "dev-requirements.txt",
      "require.txt",
      "require-test.txt",
      "py3-require.txt",
      "pyenv_require_e2e.txt",
      "dependencies.txt",
      "my-dependencies.txt",
      "depend.txt",
      "depends.txt",
      "py3-depends.txt"
    ].each do |name|
      it "treats #{name} as a manifest" do
        expect(described_class.manifest_txt_filename?(name)).to be(true)
      end
    end

    [
      "README.txt",
      "notes.txt",
      "output.txt",
      "constraints.txt",
      "LICENSE.txt",
      "prequire.txt",
      "acquire.txt",
      "codependent.txt"
    ].each do |name|
      it "does not treat #{name} as a manifest" do
        expect(described_class.manifest_txt_filename?(name)).to be(false)
      end
    end
  end

  describe "#groups" do
    context "with several independent requirements manifests" do
      let(:dependency_files) do
        [
          file("base-requirements.txt", "foo==1.0\n"),
          file("test-requirements.txt", "bar==2.0\n"),
          file("notes.txt", "not a manifest\n")
        ]
      end

      it "emits one group per manifest, each attributed to its own file" do
        expect(layers.groups.map { |g| g.primary.name })
          .to contain_exactly("base-requirements.txt", "test-requirements.txt")
      end

      it "excludes .txt files that do not look like manifests" do
        all_files = layers.groups.flat_map { |g| g.files.map(&:name) }
        expect(all_files).not_to include("notes.txt")
      end
    end

    context "with a pip-compile .in paired to a compiled .txt" do
      let(:dependency_files) do
        [
          file("requirements.in", "foo\n"),
          file("requirements.txt", "foo==1.0\n")
        ]
      end

      it "emits a single group attributed to the compiled .txt" do
        expect(layers.groups.map { |g| g.primary.name }).to eq(["requirements.txt"])
      end

      it "includes the paired .in as a support file" do
        group = layers.groups.first
        in_file = group.files.find { |f| f.name == "requirements.in" }

        expect(in_file).not_to be_nil
        expect(in_file).to be_support_file
      end

      it "keeps the primary as a non-support file" do
        expect(layers.groups.first.primary).not_to be_support_file
      end
    end

    context "with a bare .in that has no compiled .txt" do
      let(:dependency_files) do
        [
          file("requirements.in", "foo\n"),
          file("dev-requirements.in", "bar\n")
        ]
      end

      it "treats each .in as its own primary" do
        expect(layers.groups.map { |g| g.primary.name })
          .to contain_exactly("requirements.in", "dev-requirements.in")
      end
    end

    context "with a manifest that references a sibling via -r" do
      let(:dependency_files) do
        [
          file("base-requirements.txt", "foo==1.0\n"),
          file("test-requirements.txt", "-r base-requirements.txt\nbar==2.0\n")
        ]
      end

      it "includes the referenced sibling in the referencing group as a support file" do
        test_group = layers.groups.find { |g| g.primary.name == "test-requirements.txt" }
        base = test_group.files.find { |f| f.name == "base-requirements.txt" }

        expect(base).not_to be_nil
        expect(base).to be_support_file
      end
    end

    context "with a transitive -r chain three files deep" do
      let(:dependency_files) do
        [
          file("base.in", "foo==1.0\n"),
          file("test.in", "-r base.in\nbar==2.0\n"),
          file("develop.in", "-r test.in\nbaz==3.0\n")
        ]
      end

      it "includes every transitively referenced file in the referencing group as support files" do
        develop_group = layers.groups.find { |g| g.primary.name == "develop.in" }
        names = develop_group.files.map(&:name)

        expect(names).to include("test.in", "base.in")
        expect(develop_group.files.select(&:support_file?).map(&:name)).to include("test.in", "base.in")
      end
    end

    context "with a shared constraints file" do
      let(:dependency_files) do
        [
          file("base-requirements.txt", "-c constraints.txt\nfoo==1.0\n"),
          file("test-requirements.txt", "-c constraints.txt\nbar==2.0\n"),
          file("constraints.txt", "foo<2.0\n")
        ]
      end

      it "does not treat the constraints file as its own group" do
        expect(layers.groups.map { |g| g.primary.name })
          .to contain_exactly("base-requirements.txt", "test-requirements.txt")
      end

      it "includes the constraints file in every group as a support file" do
        layers.groups.each do |group|
          constraints = group.files.find { |f| f.name == "constraints.txt" }

          expect(constraints).not_to be_nil
          expect(constraints).to be_support_file
        end
      end
    end

    context "with a manifest-named constraints file referenced via `-c`" do
      let(:dependency_files) do
        [
          file("requirements.txt", "-c requirements-constraints.txt\nflask==3.0.0\n"),
          file("requirements-constraints.txt", "certifi==2023.7.22\n")
        ]
      end

      it "does not treat the `-c` file as its own layer even though its name looks like a manifest" do
        expect(layers.groups.map { |g| g.primary.name }).to eq(["requirements.txt"])
      end

      it "includes the `-c` file as a support file rather than a primary" do
        group = layers.groups.first
        constraint = group.files.find { |f| f.name == "requirements-constraints.txt" }

        expect(constraint).not_to be_nil
        expect(constraint).to be_support_file
      end
    end

    context "when a file is both `-r`-included and `-c`-constrained" do
      let(:dependency_files) do
        [
          file("dev-requirements.txt", "-r base-requirements.txt\n-c base-requirements.txt\npytest==8.3.3\n"),
          file("base-requirements.txt", "flask==3.0.0\n")
        ]
      end

      it "keeps the `-r`-included file layer-eligible (constraints do not override a real include)" do
        expect(layers.groups.map { |g| g.primary.name })
          .to contain_exactly("dev-requirements.txt", "base-requirements.txt")
      end
    end

    context "with a single requirements manifest" do
      let(:dependency_files) { [file("requirements.txt", "foo==1.0\n")] }

      it "emits a single group" do
        expect(layers.groups.map { |g| g.primary.name }).to eq(["requirements.txt"])
      end
    end
  end
end
