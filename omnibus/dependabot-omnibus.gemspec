# frozen_string_literal: true

Gem::Specification.new do |spec|
  common_gemspec =
    Bundler.load_gemspec_uncached("../common/dependabot-common.gemspec")

  spec.name         = "dependabot-omnibus"
  spec.summary      = "Meta-package that depends on all dependabot package " \
                      "managers"
  spec.version      = common_gemspec.version
  spec.description  = common_gemspec.description

  spec.author       = common_gemspec.author
  spec.email        = common_gemspec.email
  spec.homepage     = common_gemspec.homepage
  spec.license      = common_gemspec.license

  spec.required_ruby_version = ">= 3.1.0"
  spec.require_path = "lib"
  spec.files        = ["lib/dependabot/omnibus.rb"]

  spec.add_dependency "dependabot-bundler", Dependabot::VERSION
  spec.add_dependency "dependabot-cargo", Dependabot::VERSION
  spec.add_dependency "dependabot-common", Dependabot::VERSION
  spec.add_dependency "dependabot-composer", Dependabot::VERSION
  spec.add_dependency "dependabot-docker", Dependabot::VERSION
  spec.add_dependency "dependabot-elm", Dependabot::VERSION
  spec.add_dependency "dependabot-github_actions", Dependabot::VERSION
  spec.add_dependency "dependabot-git_submodules", Dependabot::VERSION
  spec.add_dependency "dependabot-go_modules", Dependabot::VERSION
  spec.add_dependency "dependabot-gradle", Dependabot::VERSION
  spec.add_dependency "dependabot-hex", Dependabot::VERSION
  spec.add_dependency "dependabot-maven", Dependabot::VERSION
  spec.add_dependency "dependabot-npm_and_yarn", Dependabot::VERSION
  spec.add_dependency "dependabot-nuget", Dependabot::VERSION
  spec.add_dependency "dependabot-pub", Dependabot::VERSION
  spec.add_dependency "dependabot-python", Dependabot::VERSION
  spec.add_dependency "dependabot-terraform", Dependabot::VERSION

  common_gemspec.development_dependencies.each do |dep|
    spec.add_development_dependency dep.name, *dep.requirement.as_list
  end
end
