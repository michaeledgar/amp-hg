begin
  require 'amp-hg/mercurial_patch/CMercurialPatch'
rescue LoadError
  require 'pure_ruby/ruby_mercurial_patch'
end
