# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/name_normaliser"

RSpec.describe Dependabot::Conda::NameNormaliser do
  describe ".normalise" do
    it "converts underscores to hyphens" do
      expect(described_class.normalise("package_name")).to eq("package-name")
      expect(described_class.normalise("my_awesome_package")).to eq("my-awesome-package")
    end

    it "converts dots to hyphens" do
      expect(described_class.normalise("package.name")).to eq("package-name")
      expect(described_class.normalise("my.awesome.package")).to eq("my-awesome-package")
    end

    it "converts mixed separators to hyphens" do
      expect(described_class.normalise("package_name.with.mixed")).to eq("package-name-with-mixed")
    end

    it "converts to lowercase" do
      expect(described_class.normalise("PackageName")).to eq("packagename")
      expect(described_class.normalise("PACKAGE_NAME")).to eq("package-name")
      expect(described_class.normalise("Package.Name")).to eq("package-name")
    end

    it "handles already normalized names" do
      expect(described_class.normalise("package-name")).to eq("package-name")
      expect(described_class.normalise("my-awesome-package")).to eq("my-awesome-package")
    end

    it "handles empty and edge cases" do
      expect(described_class.normalise("")).to eq("")
      expect(described_class.normalise("a")).to eq("a")
      expect(described_class.normalise("-")).to eq("-")
    end

    it "handles consecutive separators" do
      expect(described_class.normalise("package__name")).to eq("package--name")
      expect(described_class.normalise("package..name")).to eq("package--name")
      expect(described_class.normalise("package_.name")).to eq("package--name")
    end

    it "handles real Python package names" do
      expect(described_class.normalise("scikit_learn")).to eq("scikit-learn")
      expect(described_class.normalise("python_dateutil")).to eq("python-dateutil")
      expect(described_class.normalise("matplotlib_base")).to eq("matplotlib-base")
      expect(described_class.normalise("PyQt5")).to eq("pyqt5")
    end
  end
end
