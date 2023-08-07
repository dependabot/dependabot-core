
Gem::Specification.new do |s|
  s.name    = "library"
  s.summary = "A Library"
  s.version = "1.0.0"
  s.homepage = "https://github.com/dependabot/dependabot-core"
  s.authors = %w[monalisa]

  s.add_runtime_dependency "rubocop", "~> 0.76.0"
  s.add_runtime_dependency "toml-rb", "~> 2.2.0"
  s.add_runtime_dependency "rack", "~> 2.1.4"
end
