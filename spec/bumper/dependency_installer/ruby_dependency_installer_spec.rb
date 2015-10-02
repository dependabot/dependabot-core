require "spec_helper"
require "tmpdir"
require "bumper/dependency_file"
require "bumper/dependency"
require "bumper/dependency_installer/ruby_dependency_installer"

RSpec.describe DependencyInstaller::RubyDependencyInstaller do
  let(:gemfile) { File.read("spec/fixtures/Gemfile") }
  let(:dependency) { Dependency.new(name: "business", version: "1.5.0") }
  let(:installer) { DependencyInstaller::RubyDependencyInstaller.new(gemfile, dependency) }
  let(:tmp_path) { DependencyInstaller::RubyDependencyInstaller::BUMP_TMP_DIR_PATH }
  subject(:install) { installer.install }

  it "cleans up after install" do
    expect { install }.to_not change { Dir.entries(tmp_path) }
  end

  its(:length) { is_expected.to eq(2) }

  it "returns an array of DependencyFiles" do
    install.each { |file| expect(file).to be_a(DependencyFile) }
  end

  describe "the Gemfile.lock" do
    subject(:file) { install.find { |file| file.name == "Gemfile.lock" } }

    it "has an updated version" do
      # FIXME: find a way to parse Gemfile.lock, the current pattern matcher will fail
      # requirement = file.content.match(Gemnasium::Parser::Patterns::GEM_CALL)[5]
      expect(file.content).to include "1.5.0"
    end
  end

  describe "the Gemfile" do
    subject(:file) { install.find { |file| file.name == "Gemfile" } }

    it "has an updated version" do
      requirement = file.content.match(Gemnasium::Parser::Patterns::GEM_CALL)[5]
      expect(requirement).to include "1.5.0"
    end
  end
end
