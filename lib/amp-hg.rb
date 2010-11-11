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

    module Merges
      autoload :MergeUI,        'amp-hg/merging/merge_ui'
      autoload :ThreeWayMerger, 'amp-hg/merging/simple_merge'
      autoload :MergeState,     'amp-hg/repo_format/merge_state'
    end
    
    module RepositoryFormat
      autoload :BranchManager, 'amp-hg/repo_format/branch_manager'
      autoload :TagManager, 'amp-hg/repo_format/tag_manager'
      autoload :Updating, 'amp-hg/repo_format/updater'
      autoload :Verification, 'amp-hg/repo_format/verification'
    end
  end
end