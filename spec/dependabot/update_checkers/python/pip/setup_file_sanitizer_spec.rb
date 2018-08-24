# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/update_checkers/python/pip/setup_file_sanitizer"

RSpec.describe Dependabot::UpdateCheckers::Python::Pip::SetupFileSanitizer do
  let(:sanitizer) { described_class.new(setup_file: setup_file) }

  let(:setup_file) do
    Dependabot::DependencyFile.new(
      name: "setup.py",
      content: fixture("python", "setup_files", setup_file_fixture_name)
    )
  end
  let(:setup_file_fixture_name) { "setup.py" }

  describe "#sanitized_content" do
    subject(:sanitized_content) { sanitizer.sanitized_content }

    it "extracts the install_requires" do
      expect(sanitized_content).to eq(
        "from setuptools import setup\n\n"\
        'setup(name="python-package",version="0.0",'\
        'install_requires=["boto3==1.3.1","flake8<3.0.0,>2.5.4",'\
        '"gocardless_pro","pandas==0.19.2","pep8==1.7.0","psycopg2==2.6.1",'\
        '"raven==5.32.0","requests==2.12.*","scipy==0.18.1",'\
        '"scikit-learn==0.18.1"])'
      )
    end
  end
end
