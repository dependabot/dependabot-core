# frozen_string_literal: true

target :lib do
  Dir["*"].each do |directory|
    next unless File.directory?(directory)
    next unless Dir.exist?(File.join(directory, "sig")) && Dir.exist?(File.join(directory, "lib"))

    signature File.join(directory, "sig")
    check File.join(directory, "lib")
  end

  library "rubygems", "forwardable", "time"

  configure_code_diagnostics do |config|
    config[Steep::Diagnostic::Ruby::UnexpectedJump] = :hint
    # config[Steep::Diagnostic::Ruby::MethodDefinitionMissing] = :hint
  end
end
