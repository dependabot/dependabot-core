# frozen_string_literal: true

name = File.basename(__FILE__, ".gemspec")
version = "0.3.3"

Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors       = ["Shugo Maeda", "nicholas a. evans"]
  spec.email         = ["shugo@ruby-lang.org", "nick@ekenosen.net"]

  spec.summary       = %q{Ruby client api for Internet Message Access Protocol}
  spec.description   = %q{Ruby client api for Internet Message Access Protocol}
  spec.homepage      = "https://github.com/ruby/net-imap"
end
