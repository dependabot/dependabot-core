# frozen_string_literal: true

require "cgi"
require "uri"

def pr_info(dependency)
  info = "More information can be found at: "
  if using_dockerhub? dependency
    info << URI.join(
      "https://hub.docker.com/_/",
      CGI.escape(dependency.name) + "?" +
      URI.encode_www_form([
                            %w(tab tags),
                            ["name", dependency.version]
                          ])
    ).to_s
  else
    info << URI.join("https://github.com/Pix4D/linux-image-build/releases/tag/",
                     CGI.escape("#{dependency.name}-#{dependency.version}")).to_s
  end
end

def using_dockerhub?(dependency)
  unless dependency.requirements.length == 1
    raise ArgumentError, "Dependency must have exactly one requirement"
  end

  dependency.requirements.first[:source][:registry].nil?
end
