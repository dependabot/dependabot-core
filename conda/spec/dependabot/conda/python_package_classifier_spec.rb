# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/python_package_classifier"

RSpec.describe Dependabot::Conda::PythonPackageClassifier do
  describe ".python_package?" do
    context "with known Python packages" do
      it "identifies standard Python packages (but excludes python interpreter)" do
        expect(described_class.python_package?("python")).to be(false)  # Python interpreter, not a PyPI package
        expect(described_class.python_package?("numpy")).to be(true)
        expect(described_class.python_package?("pandas")).to be(true)
        expect(described_class.python_package?("scipy")).to be(true)
        expect(described_class.python_package?("matplotlib")).to be(true)
        expect(described_class.python_package?("scikit-learn")).to be(true)
        expect(described_class.python_package?("requests")).to be(true)
        expect(described_class.python_package?("flask")).to be(true)
        expect(described_class.python_package?("django")).to be(true)
        expect(described_class.python_package?("jupyter")).to be(true)
      end

      it "identifies Python packages with variants" do
        expect(described_class.python_package?("matplotlib-base")).to be(true)
        expect(described_class.python_package?("numpy-base")).to be(true)
        expect(described_class.python_package?("python_abi")).to be(true)
      end
    end

    context "with known non-Python packages" do
      it "identifies R packages" do
        expect(described_class.python_package?("r-base")).to be(false)
        expect(described_class.python_package?("r-essentials")).to be(false)
        expect(described_class.python_package?("r-ggplot2")).to be(false)
        expect(described_class.python_package?("r-dplyr")).to be(false)
      end

      it "identifies system tools" do
        expect(described_class.python_package?("git")).to be(false)
        expect(described_class.python_package?("cmake")).to be(false)
        expect(described_class.python_package?("make")).to be(false)
        expect(described_class.python_package?("gcc")).to be(false)
        expect(described_class.python_package?("wget")).to be(false)
        expect(described_class.python_package?("curl")).to be(false)
      end

      it "identifies system libraries" do
        expect(described_class.python_package?("openssl")).to be(false)
        expect(described_class.python_package?("zlib")).to be(false)
        expect(described_class.python_package?("libffi")).to be(false)
        expect(described_class.python_package?("ncurses")).to be(false)
        expect(described_class.python_package?("readline")).to be(false)
      end

      it "identifies compiler and build tools" do
        expect(described_class.python_package?("_libgcc_mutex")).to be(false)
        expect(described_class.python_package?("_openmp_mutex")).to be(false)
        expect(described_class.python_package?("binutils")).to be(false)
        expect(described_class.python_package?("gxx_linux-64")).to be(false)
      end

      it "identifies multimedia libraries" do
        expect(described_class.python_package?("ffmpeg")).to be(false)
        expect(described_class.python_package?("opencv")).to be(false)
        expect(described_class.python_package?("imageio")).to be(false)
      end
    end

    context "with ambiguous package names" do
      it "uses heuristics for unknown packages" do
        # Packages with 'py' prefix are likely Python
        expect(described_class.python_package?("pyqt")).to be(true)
        expect(described_class.python_package?("pycrypto")).to be(true)

        # Packages ending with common Python patterns
        expect(described_class.python_package?("somepackage.py")).to be(true)

        # Short names are now treated as Python packages (default to true)
        expect(described_class.python_package?("abc")).to be(true)
        expect(described_class.python_package?("xyz")).to be(true)
      end

      it "handles edge cases" do
        expect(described_class.python_package?("")).to be(false)
        expect(described_class.python_package?("unknown-package-name")).to be(true)
      end
    end

    context "with package names containing versions or extras" do
      it "strips version information for classification" do
        expect(described_class.python_package?("numpy=1.21.0")).to be(true)
        expect(described_class.python_package?("pandas>=1.3.0")).to be(true)
        expect(described_class.python_package?("r-base=4.0.3")).to be(false)
      end
    end
  end
end
