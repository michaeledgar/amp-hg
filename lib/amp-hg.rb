puts 'Loading amp-hg...'

require 'zlib'
require 'stringio'

# Must require the HgPicker or it won't be found.
require 'amp-hg/repository.rb'

module Amp
  module Mercurial
    module Diffs
      autoload :MercurialDiff,  'amp-hg/encoding/mercurial_diff'
      autoload :MercurialPatch, 'amp-hg/encoding/mercurial_patch'
    end
  end
end