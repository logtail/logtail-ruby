# -*- encoding: utf-8 -*-
$LOAD_PATH.push File.expand_path("../lib", __FILE__)
require "logtail/version"

Gem::Specification.new do |spec|
  spec.name          = "logtail"
  spec.version       = Logtail::VERSION
  spec.platform      = Gem::Platform::RUBY
  spec.authors       = ["Better Stack"]
  spec.email         = ["hello@betterstack.com"]
  spec.homepage      = "https://github.com/logtail/logtail-ruby"
  spec.license       = "ISC"

  spec.summary       = "Query logs like you query your database. https://logs.betterstack.com/"

  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/tree/master/CHANGELOG.md"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.required_ruby_version = Gem::Requirement.new(">= 2.3")

  spec.files         = `git ls-files`.split("\n")
  spec.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  spec.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency('msgpack', '~> 1.0')

  spec.add_development_dependency('bundler-audit', '>= 0')
  spec.add_development_dependency('rails_stdout_logging', '>= 0')
  spec.add_development_dependency('rake', '>= 0')
  spec.add_development_dependency('rspec', '~> 3.4')
  spec.add_development_dependency('rspec-its', '>= 0')
  spec.add_development_dependency('timecop', '>= 0')
  spec.add_development_dependency('webmock', '~> 2.3')
end
