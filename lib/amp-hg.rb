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
      autoload :DirState, 'amp-hg/repo_format/dir_state'
      autoload :Lock, 'amp-hg/repo_format/lock'
      autoload :Stores, 'amp-hg/repo_format/store'
      autoload :TagManager, 'amp-hg/repo_format/tag_manager'
      autoload :Updating, 'amp-hg/repo_format/updater'
      autoload :Verification, 'amp-hg/repo_format/verification'
    end
    
    module Repositories
      autoload :BundleRepository, 'amp-hg/repositories/bundle_repository'
      autoload :HTTPRepository, 'amp-hg/repositories/http_repository'
      autoload :LocalRepository, 'amp-hg/repositories/local_repository'
    end
    
    module Revlogs
      autoload :BundleRevlog, 'amp-hg/revlogs/bundle_revlogs'
      autoload :ChangeLog, 'amp-hg/revlogs/changelog'
      autoload :FileLog, 'amp-hg/revlogs/file_log'
    end
    
    module RevlogSupport
      autoload :ChangeGroup, 'amp-hg/revlogs/changegroup'
      autoload :Index, 'amp-hg/revlogs/index'
      autoload :Manifest, 'amp-hg/revlogs/manifest'
      autoload :Node, 'amp-hg/revlogs/node'
      autoload :Support, 'amp-hg/revlogs/revlog_support'
    end
    
    autoload :Changeset, 'amp-hg/repo_format/changeset'
    autoload :WorkingDirectoryChangeset, 'amp-hg/repo_format/changeset'
    autoload :Journal, 'amp-hg/repo_format/journal'
    autoload :Revlog, 'amp-hg/revlogs/revlog'
    autoload :StagingArea, 'amp-hg/repo_format/staging_area'
    autoload :VersionedFile, 'amp-hg/repo_format/versioned_file'
  end
end