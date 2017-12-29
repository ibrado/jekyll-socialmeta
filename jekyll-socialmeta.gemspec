
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "jekyll/socialmeta/version"

Gem::Specification.new do |spec|
  spec.name          = "jekyll-socialmeta"
  spec.version       = Jekyll::SocialMeta::VERSION
  spec.required_ruby_version = '>= 2.0.0'
  spec.authors       = ["Alex Ibrado"]
  spec.email         = ["alex@ibrado.org"]

  spec.summary       = %q{SocialMeta: Make your site preview look good when shared on social media sites.}
  spec.description   = %q{SocialMeta: Automatically generate the preview image and description for your content when you share it on social media sites. Uses and resizes largest image it can find on your page, and can even generate screenshots of your page or other websites.}
  spec.homepage      = "https://github.com/ibrado/jekyll-socialmeta"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "jekyll", "~> 3.0"
  spec.add_runtime_dependency "phantomjs", "~> 2.1"
  spec.add_runtime_dependency "fastimage", "~> 2.1"

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
