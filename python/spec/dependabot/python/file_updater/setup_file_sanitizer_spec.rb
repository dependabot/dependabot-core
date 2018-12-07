# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/setup_file_sanitizer"

RSpec.describe Dependabot::Python::FileUpdater::SetupFileSanitizer do
  let(:sanitizer) do
    described_class.new(setup_file: setup_file, setup_cfg: setup_cfg)
  end

  let(:setup_file) do
    Dependabot::DependencyFile.new(
      name: "setup.py",
      content: fixture("python", "setup_files", setup_file_fixture_name)
    )
  end
  let(:setup_cfg) { nil }
  let(:setup_file_fixture_name) { "setup.py" }

  describe "#sanitized_content" do
    subject(:sanitized_content) { sanitizer.sanitized_content }

    it "extracts the install_requires" do
      expect(sanitized_content).to eq(
        "from setuptools import setup\n\n"\
        'setup(name="sanitized-package",version="0.0.1",'\
        'install_requires=["boto3==1.3.1","flake8<3.0.0,>2.5.4",'\
        '"gocardless-pro","pandas==0.19.2","pep8==1.7.0","psycopg2==2.6.1",'\
        '"raven==5.32.0","requests==2.12.*","scipy==0.18.1",'\
        '"scikit-learn==0.18.1"],extras_require={"API":["flask==0.12.2"]})'
      )
    end

    context "for a setup.py using pbr" do
      let(:setup_file_fixture_name) { "with_pbr.py" }
      let(:setup_cfg) do
        Dependabot::DependencyFile.new(
          name: "setup.cfg",
          content: fixture("python", "setup_files", "setup.cfg")
        )
      end

      it "includes pbr" do
        expect(sanitized_content).to eq(
          "from setuptools import setup\n\n"\
          'setup(name="sanitized-package",version="0.0.1",'\
          'install_requires=["raven"],extras_require={},'\
          'setup_requires=["pbr"],pbr=True)'
        )
      end
    end
  end
end
