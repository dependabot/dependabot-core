# frozen_string_literal: true

require "dependabot/pr_info"
require "dependabot/dependency"

def make_dependency_with_registry(registry)
  requirement = {
    requirement: nil,
    groups: [],
    file: "",
    source: {}
  }

  requirement[:source][:registry] = registry unless registry.nil?

  Dependabot::Dependency.new(
    name: "python",
    version: "3.8.0",
    requirements: [requirement],
    package_manager: nil
  )
end

RSpec.describe "pr_info", :pix4d do
  context "using a private registry" do
    it "links to Pix4D image builder repo" do
      dependency = make_dependency_with_registry("docker.ci.pix4d.com")
      expect(pr_info(dependency)).
        to include("https://github.com/Pix4D/linux-image-build/releases/tag/python-3.8.0")
    end
  end

  context "using a public registry" do
    it "links to DockerHub search page" do
      dependency = make_dependency_with_registry(nil)
      expect(pr_info(dependency)).
        to include("https://hub.docker.com/_/python?tab=tags&name=3.8.0")
    end
  end
end
