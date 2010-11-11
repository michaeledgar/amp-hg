#######################################################################
#                  Licensing Information                              #
#                                                                     #
#  The following code is a derivative work of the code from the       #
#  Mercurial project, which is licensed GPLv2. This code therefore    #
#  is also licensed under the terms of the GNU Public License,        #
#  verison 2.                                                         #
#                                                                     #
#  For information on the license of this code when distributed       #
#  with and used in conjunction with the other modules in the         #
#  Amp project, please see the root-level LICENSE file.               #
#                                                                     #
#  © Michael J. Edgar and Ari Brown, 2009-2010                        #
#                                                                     #
#######################################################################

module Amp
  module Mercurial
    module Merges
      
      ##
      # = MergeState
      # MergeState handles the merge/ directory in the repository, in order
      # to keep track of how well the current merge is progressing. There is
      # a file called merge/state that lists all the files that need merging
      # and a little info about whether it has beeen merged or not.
      #
      # You can add a file to the mergestate, iterate over all of them, quickly
      # look up to see if a file is still dirty, and so on.
      class MergeState
        include Enumerable
        
        ##
        # Initializes a new mergestate with the given repo, and reads in all the
        # information from merge/state.
        #
        # @param repo the repository being inspected
        def initialize(repo)
          @repo = repo
          read!
        end
        
        ##
        # Resets the merge status, by clearing all merge information and files
        # 
        # @param node the node we're working with? seems kinda useless
        def reset(node = nil)
          @state = {}
          @local = node if node
          FileUtils.rm_rf @repo.join("merge")
        end
        alias_method :reset!, :reset
        
        ##
        # Returns whether the file is part of a merge or not
        # 
        # @return [Boolean] if the dirty file in our state and not nil?
        def include?(dirty_file)
          not @state[dirty_file].nil?
        end
        
        ##
        # Accesses the the given file's merge status - can be "u" for unmerged,
        # or other stuff we haven't figured out yet.
        #
        # @param [String] dirty_file the path to the file for merging.
        # @return [String] the status as a letter - so far "u" means unmerged or "r"
        #   for resolved.
        def [](dirty_file)
          @state[dirty_file] ? @state[dirty_file][0, 1] : ""
        end
        
        ##
        # Adds a file to the mergestate, which creates a separate file
        # in the merge directory with all the information. I don't know
        # what these parameters are for yet.
        def add(fcl, fco, fca, fd, flags)
          hash = Digest::SHA1.new.update(fcl.path).hexdigest
          @repo.open("merge/#{hash}", "w") do |file|
            file.write fcl.data
          end
          @state[fd] = ["u", hash, fcl.path, fca.path, fca.file_node.hexlify,
                        fco.path, flags]
          save
        end
        
        ##
        # Returns all uncommitted merge files - everything tracked by the merge state.
        #
        # @todo come up with a better method name
        #
        # @return [Array<Array<String, Symbol>>] an array of String-Symbol pairs - the
        #   filename is the first entry, the status of the merge is the second.
        def uncommitted_merge_files
          @state.map {|k, _| [k, status(k)] }
        end
        
        ##
        # Iterates over all the files that are involved in the current
        # merging transaction.
        #
        # @yield each file, sorted by filename, that needs merging.
        # @yieldparam file the filename that needs (or has been) merged.
        # @yieldparam state all the information about the current merge with
        #   this file.
        def each(&block)
          @state.each(&block)
        end
        
        ##
        # Marks the given file with a given state, which is 1 letter. "u" means
        # unmerged, "r" means resolved.
        #
        # @param [String] dirty_file the file path for marking
        # @param [String] state the state - "u" for unmerged, "r" for resolved.
        def mark(dirty_file, state)
          @state[dirty_file][0] = state
          save
        end
        
        ##
        # Marks the given file as unresolved. Helper method to hide details of
        # how the mergestate works. Silly leaky abstractions...
        #
        # @param [String] filename the file to mark unresolved
        def mark_conflicted(filename)
          mark(filename, "u")
        end
        
        ##
        # Marks the given file as resolved. Helper method to hide details of
        # how the mergestate works. Silly leaky abstractions...
        #
        # @param [String] filename the file to mark unresolved
        def mark_resolved(filename)
          mark(filename, "r")
        end
        
        ##
        # Returns the status of a given file, or nil otherwise. Used for making this
        # class more friendly to the outside world. It came to us from mercurial as
        # one leaky fucking abstraction. Every class that used it had to know that "u"
        # returned meant unresolved... ugh.
        #
        # @param [String] filename the file to inspect
        # @return [Symbol] a symbol representing the status of the file, either
        #   :untracked, :resolved, or :unresolved
        def status(filename)
          return :untracked unless filename
          case self[filename]
          when "r"
            :resolved
          when "u"
            :unresolved
          end
        end
        
        ##
        # Is the given file unresolved?
        #
        # @param [String] filename
        def unresolved?(filename)
          status(filename) == :unresolved
        end
        
        ##
        # Is the given file resolved?
        #
        # @param [String] filename
        def resolved?(filename)
          status(filename) == :resolved
        end
        
        ##
        # Resolves the given file for a merge between 2 changesets.
        #
        # @param dirty_file the path to the file for merging
        # @param working_changeset the current changeset that is the destination
        #   of the merge
        # @param other_changeset the newer changeset, which we're merging to
        def resolve(dirty_file, working_changeset, other_changeset)
          return 0 if resolved?(dirty_file)
          state, hash, lfile, afile, anode, ofile, flags = @state[dirty_file]
          r = true
          @repo.open("merge/#{hash}") do |file|
            @repo.working_write(dirty_file, file.read, flags)
            working_file  = working_changeset[dirty_file]
            other_file    = other_changeset[ofile]
            ancestor_file = @repo.versioned_file(afile, :file_id => anode)
            r = MergeUI.file_merge(@repo, @local, lfile, working_file, other_file, ancestor_file)
          end
          
          mark_resolved(dirty_file) if r.nil? || r == false
          return r
        end
        
        ##
        # Public access to writing the file.
        def save
          write!
        end
        alias_method :save!, :save
        
        private
        
        ##
        # Reads in the merge state and sets up all our instance variables.
        #
        def read!
          @state = {}
          ignore_missing_files do
            local_node = nil
            @repo.open("merge/state") do |file|
              get_node = true
              file.each_line do |line|
                if get_node
                  local_node = line.chomp
                  get_node = false
                else
                  parts = line.chomp.split("\0")
                  @state[parts[0]] = parts[1..-1]
                end
              end
              @local = local_node.unhexlify
            end
          end
        end
        
        ##
        # Saves the merge state to disk.
        #
        def write!
          @repo.open("merge/state","w") do |file|
            file.write @local.hexlify + "\n"
            @state.each do |key, val|
              file.write "#{([key] + val).join("\0")}\n"
            end
          end
        end
        
      end
    end
  end
end