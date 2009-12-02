require 'rake'
begin
  $: << File.join(File.dirname(__FILE__),'lib')
  require 'contentdm'
  Gem::Specification.new do |s|
    s.name = "contentdm"
    s.version = ContentDm::VERSION
    s.summary = "Access to structured metadata in CONTENTdm collections"
    s.email = "Michael.Klein@oregonstate.edu"
    s.description = "Module providing access to structured metadata in CONTENTdm collections"
    s.authors = ["Michael B. Klein"]
    s.files = FileList["[A-Z]*", "README.rdoc", "{bin,lib,test}/**/*"]
    s.extra_rdoc_files = ['README.rdoc']
    s.add_dependency 'nokogiri'
  end
rescue LoadError
  puts "Error loading ContentDm module."
end
