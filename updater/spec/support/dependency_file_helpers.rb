# frozen_string_literal: true

module DependencyFileHelpers
  def encode_dependency_files(files)
    files.map do |file|
      base64_file = file.dup
      base64_file.content = Base64.encode64(file.content) unless file.binary?
      base64_file.to_h
    end
  end
end
