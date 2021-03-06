
# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

open("ext/numo/gsl/version.h") do |f|
  f.each_line do |l|
    if /NUMO_GSL_VERSION "([\d.]+)"/ =~ l
      VERSION = $1
      break
    end
  end
end

Gem::Specification.new do |spec|
  spec.name          = "numo-gsl"
  spec.version       = VERSION
  spec.authors       = ["Masahiro TANAKA"]
  spec.email         = ["masa16.tanaka@gmail.com"]
  spec.description   = %q{Numo::Gsl development version.}
  spec.summary       = %q{Numo::Gsl development version}
  spec.homepage      = "https://github.com/ruby-numo/gsl"
  spec.license       = "GPL-3"

  spec.files         = `git ls-files Gemfile README.md Rakefile ext lib numo-gsl.gemspec spec`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.extensions    = %w[
ext/numo/gsl/const/extconf.rb
ext/numo/gsl/sys/extconf.rb
ext/numo/gsl/sf/extconf.rb
]
  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake", "~> 0"
  spec.add_runtime_dependency "numo-narray", "~> 0.9"
end
