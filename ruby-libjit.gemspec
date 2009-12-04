require 'enumerator'

spec = Gem::Specification.new do |s|
  s.name = 'ruby-libjit'
  s.version = File.read('VERSION').chomp
  s.summary = 'A wrapper for the libjit library'
  s.homepage = 'http://ruby-libjit.rubyforge.org'
  s.rubyforge_project = 'ruby-libjit'
  s.author = 'Paul Brannan'
  s.email = 'curlypaul924@gmail.com'

  s.description = <<-END
Ruby-libjit is a wrapper for the libjit library.  Libjit is a
lightweight library for building just-in-time compilers.  Ruby-libjit
includes both a wrapper for libjit and a minimal DSL for building loops
and control structures.
  END


  patterns = [
    'VERSION'
    'COPYING',
    'LGPL',
    'LICENSE',
    'README',
    'lib/*.rb',
    'lib/jit/*.rb',
    'ext/*.rb',
    'ext/*.c',
    'ext/*.h',
    'ext/*.rpp',
    'sample/*.rb',
  ]

  s.files = patterns.collect { |p| Dir.glob(p) }.flatten

  s.test_files = Dir.glob('test/test_*.rb')

  s.extensions = 'ext/extconf.rb'

  s.has_rdoc = true
end

