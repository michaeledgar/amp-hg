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
    module RevlogSupport
      include Node
      
      ##
      # This class represents one revision entry in the index.
      #
      # Format on disk (in BitStruct notation):
      #
      #       default_options :endian => :network
      #       
      #       signed :offset_flags, 64
      #       signed :compressed_len, 32
      #       signed :uncompressed_len, 32
      #       signed :base_rev, 32
      #       signed :link_rev, 32
      #       signed :parent_one_rev, 32
      #       signed :parent_two_rev, 32
      #       char :node_id, 160
      #       pad  :padding, 96
      #
      # [offset_flags] - this is a double-word (8 bytes) - that combines the offset into the data file
      # and any flags about the entry
      # [compressed_len] - this is the length of the data when compressed
      # [uncompresed_len] - length of the data uncompresed
      # [base_rev] - the revision of the filelog
      # [link_rev] - the revision of the whole repo where this was attached
      # [parent_one_rev] - the parent revision the revision. Even if it's not a merge,
      # it will have at least this parent entry
      # [parent_two_rev] - if the revision is a merge, then it will have a second parent.
      class IndexEntry < Struct.new(:offset_flags, :compressed_len, :uncompressed_len, :base_rev,
                                    :link_rev, :parent_one_rev, :parent_two_rev, :node_id)
        include Comparable
        
        INDEX_FORMAT_NG = "Q NNNNNN a20 x12"
        BLOCK_SIZE = 64
        
        def initialize(*args)
          if args.size == 1 && args[0].respond_to?(:read)
            super(*(args[0].read(BLOCK_SIZE).unpack(INDEX_FORMAT_NG)))
          else
            super(*args)
          end
        end
        
        def to_s
          fix_signs
          ret = self.to_a.pack(INDEX_FORMAT_NG)
          fix_signs
          ret
        end
        
        ##
        # This bears some explanation.
        #
        # Rather than simply having a 4-byte header for the index file format, the
        # Mercurial format takes the first entry in the index, and stores the header
        # in its offset field. (The offset field is a 64-bit unsigned integer which
        # stores the offset into the data or index of the associated record's data)
        # They take advantage of the fact that the first entry's offset will always
        # be 0. As such, its offset field is always going to be zero, so it's safe
        # to store data there.
        #
        # The format is ((flags << 16) | (version)), where +flags+ is a bitmask (up to 48
        # bits) and +version+ is a 16-bit unsigned short.
        #
        # The worst part is, EVERY SINGLE ENTRY has its offset shifted 16 bits to the left,
        # apparently all because of this. It fucking baffles my mind. I mean... I guess now
        # there are flags available if they ever add per-revision flags... but they haven't
        # yet. And the flags could've just been in the top 16 bits
        #
        # So yeah. offset = value >> 16.
        def true_offset
          offset_flags >> 16
        end
        
        ##
        # Sets the offset value of the entry. Needed because offset and flags are two merged
        # fields.
        #
        # @param [Fixnum] val the value to set as the new offset
        def true_offset=(val)
          self.offset_flags = (offset_flags & 0xffff) | (val << 16)
        end
        
        ##
        # Sets the flags of the entry. Needed because offset and flags are two merged fields.
        #
        # @param [Fixnum] val the new flags to set
        def flags=(val)
          self.offset_flags = (offset_flags & 0xffffffffffff0000) | val
        end
        
        # Fixes the values to force them to be signed (possible to be negative)
        def fix_signs
          self.offset_flags     = Support::EncodingUtils.network_to_host_64(self.offset_flags)
          self.parent_one_rev   = self.parent_one_rev.to_signed_32
          self.parent_two_rev   = self.parent_two_rev.to_signed_32
          
          self
        end
        
        # Compares this entry to another
        def <=> other_entry
          this.base_rev <=> other_entry.base_rev
        end
        
        # Gives a hash value so we can stick these entries into a hash
        def hash
          node_id.hash
        end
      end
      
      ##
      # = Index
      # The Index is a file that keeps track of the revision data. All revisions
      # go through an index. This class, {Index}, is the most basic class. It
      # provides an Index.parse method so that you can read a file in, and
      # the class will figure out which version it is, and all that jazz.
      #
      class Index
        include Mercurial::RevlogSupport::Support
        include Enumerable
        
        # This is the packed format of the version number of the index.
        VERSION_FORMAT = "N"
        # The version (either {REVLOG_VERSION_0} or {REVLOG_VERSION_NG})
        attr_reader :version
        # The actual lookup array. Each revision has an index in this list, and
        # that list also happens to be relatively chronological.
        attr_reader :index
        # This node_map lets you look up node_id's (NOT INDEX-NUMBERS),
        # which are strings, and get the index into @index of the
        # node you're looking up.
        attr_reader :node_map
        # This allows a couple neat caching tricks to speed up acces and cut
        # down on IO.
        attr_reader :chunk_cache
        # This is the path to the index file. Can be a URL. I don't care and
        # neither should you.
        attr_reader :indexfile
        # This is the raw cache data. Another helpful bit.
        attr_accessor :cache
        
        ##
        # This method will parse the file at the provided path and return
        # an appropriate Index object. The object will be of the class that
        # fits the file provided, based on version and whether
        # it is inline.
        # 
        # @param [String] inputfile the filepath to load and parse
        # @return [Index] Some subclassed version of Index that's parsed the file
        def self.parse(opener, inputfile)
          versioninfo = REVLOG_DEFAULT_VERSION
          
          begin
            i = nil
            opener.open(inputfile) do |f|
              i = f.read(4)
            end
            versioninfo = i.unpack(VERSION_FORMAT).first if i
            # Check if the data is with the index info.
            inline = versioninfo & REVLOG_NG_INLINE_DATA > 0
            # Get the version number of the index file.
            version = get_version versioninfo
          rescue
            inline = true
            version = REVLOG_VERSION_NG
          end
          # Get a lazy subclass if we're not inline and huge.
          opener_filename = opener.join(inputfile)
          if version == REVLOG_VERSION_NG && !inline && File.exist?(opener_filename) && File.size(opener_filename) > 25.kb
            return LazyIndex.new opener, inputfile
          end
          
          # Pick a subclass for the version and in-line-icity we found.
          case [version, inline]
          when [REVLOG_VERSION_0, false]
            IndexVersion0.new opener, inputfile
          when [REVLOG_VERSION_NG, false]
            IndexVersionNG.new opener, inputfile
          when [REVLOG_VERSION_NG, true]
            IndexInlineNG.new opener, inputfile
          else
            raise RevlogError.new("Invalid format: #{version} flags: #{get_flags(versioninfo)}")
          end
        end
        
        ##
        # Extracts the version of the revlog from the offset/flags value provided.
        #
        # And yeah. version = value && 0xFFFF (last 16 bits)
        def self.get_version(t)
          t & 0xFFFF
        end
        
        ##
        # Returns whether a given node ID exists, without throwing a lookup error.
        #
        # @param [String] node the node_id to lookup. 20 bytes, binary.
        # @return [Boolean] is the node in the index?
        def has_node?(node)
          @node_map[node]
        end
        
        ##
        # This provides quick lookup into the index, based on revision
        # number. NOT ID's, index numbers.
        # 
        # @param [Fixnum] index the index to look up
        # @return [IndexEntry] the revision requested
        def [](index)
          @index[index]
        end
        
        ##
        # This method writes the index to file. Pretty 1337h4><.
        #
        # @param [String] index_file the path to the index file.
        def write_entry(index_file, journal) 
          raise abort("Use a concrete class. Yeah, I called it a concrete class. I hate" +
                               " Java too, but you tried to use an abstract class.")
        end
        
        ##
        # Adds an item to the index safely. DO NOT USE some_index.index <<. It's
        # some_index << entry.
        # 
        # @param [[Integer, Integer, Integer, Integer, Integer, Integer,
        #   Integer, Integer]] item the data to enter as an entry. See the spec fo
        #   {IndexEntry}.
        def <<(item)
          @index.insert(-2, IndexEntry.new(*item)) if item.is_a? Array
          @index.insert(-2, item) if item.is_a? IndexEntry
          # leave the terminating entry intact
        end
        
        # Returns the number of entries in the index, including the null revision
        def size
          @index.size
        end
        
        # Iterates over each entry in the index, including the null revision
        def each(&b)
          @index.each(&b)
        end
      end
      
      ##
      # = IndexVersion0
      # This handles old versions of the index file format.
      # These are apparently so old they were version 0.
      class IndexVersion0 < Index
        # Binary data format for each revision entry
        INDEX_FORMAT_V0 = "N4 a20 a20 a20"
        # The size of each revision entry
        BLOCK_SIZE = (4 * 4) + (3 * 20)
        # The offset into the entry where the SHA1 is stored for validation
        SHA1_OFFSET = 56
        
        # Return the size of 1 entry
        def entry_size; BLOCK_SIZE; end
        # Return what version this index is
        def version; REVLOG_VERSION_0; end
        # Does the index store the data with the revision index entries?
        def inline?; false; end
        
        # Initializes the index by reading from the provided filename. Users probably
        # don't need this because {Index}#{parse} will do this for you.
        # 
        # @param [String] inputfile the path to the index file
        def initialize(opener, inputfile)
          @opener = opener
          @indexfile = inputfile
          @node_map  = {Node::NULL_ID => Node::NULL_REV}
          @index = []
          n = offset = 0
          if File.exists?(opener.join(inputfile))
            opener.open(inputfile) do |f|
              
              while !f.eof?
                current = f.read(BLOCK_SIZE)
                entry = current.unpack(INDEX_FORMAT_V0)
                new_entry = IndexEntry.new(offset_version(entry[0],0), entry[1], -1, entry[2], entry[3],
                                           (@node_map[entry[4]] || nullrev), (@node_map[entry[5]] || nullrev), 
                                           entry[6])
                @index << new_entry.fix_signs
                @node_map[entry[6]] = n
                n += 1
              end
            end
          end
          @cache = nil
          self
        end
        
        ##
        # This method writes the index to file. Pretty 1337h4><.
        #
        # @param [String] index_file the path to the index file.
        def write_entry(index_file, entry, journal, data)
          curr = self.size - 1
          
          node_map[entry.last] = curr
          
          link = entry.link_rev
          data_file = index_file[0..-3] + ".d"
          
          entry = pack_entry entry, link
          
          data_file_handle  = open(data_file,  "a")
          index_file_handle = open(index_file, "a+")
          
          journal << {:file => data_file,  :offset => offset}
          journal << {:file => index_file, :offset => curr * entry.size}
          
          data_file_handle.write data[:compression] if data[:compression].any?
          data_file_handle.write data[:text]
          
          data_file_handle.flush
          index_file_handle.write entry
        end
        ##
        # This takes an entry and packs it into binary data for writing to
        # the file.
        # 
        # @param [IndexEntry] entry the revision entry to pack up for writing
        # @param rev unused by version 0. Kept to make the interface uniform
        # @return [String] the Binary data packed up for writing.
        def pack_entry(entry, rev)
          entry = IndexEntry.new(*entry) if entry.kind_of? Array
          entry.fix_signs
          e2 = [RevlogSupport::Support.offset_type(entry.offset_flags), 
                entry.compressed_len, entry.base_rev, entry.link_rev,
                @index[entry.parent_one_rev].node_id, 
                @index[entry.parent_two_rev].node_id, entry.node_id]
          e2.pack(INDEX_FORMAT_V0)
        end
      end
      
      ##
      # = IndexVersionNG
      # This is the current version of the index. I'm not sure why they call
      # it Version 'NG' but they do. An index of this type is *not* inline.
      class IndexVersionNG < Index
        VERSION_FORMAT = "N"
        # The binary format used for pack/unpack
        INDEX_FORMAT_NG = "Q NNNNNN a20 x12"
        # The distance into the entry to go to find the SHA1 hash
        SHA1_OFFSET = 32
        # The size of a single block in the index
        BLOCK_SIZE = 8 + (6 * 4) + 20 + 12
        
        ##
        # Initializes the index by parsing the given file.
        # 
        # @param [String] inputfile the path to the index file.
        def initialize(opener, inputfile)
          @opener = opener
          @indexfile = inputfile
          @cache = nil
          @index = []
          @node_map = {Node::NULL_ID => Node::NULL_REV}
                  
          opened = parse_file
          
          if opened
            fix_first_entry!
          end

          @index << IndexEntry.new(0,0,0,-1,-1,-1,-1,Node::NULL_ID)
        end
        
        ##
        # returns the size of 1 block in this type of index
        def entry_size; BLOCK_SIZE; end
        
        # returns the version number of the index
        def version; REVLOG_VERSION_NG; end
        # returns whether or not the index stores data with revision info
        def inline?; false; end
        
        ##
        # Reads in an index entry from an IO source.
        #
        # @param [IO] input the input, IO source.
        # @param [Integer] num the number of the entry
        # @return [IndexEntry] the parsed entry
        def read_entry(input, num)
          entry = IndexEntry.new(input).fix_signs
          @node_map[entry.node_id] = num
          @index << entry
          entry
        end
        
        ##
        # Parses each index entry. Internal use only.
        #
        # @return [Boolean] whether the file was opened
        def parse_file
          n = 0
          begin
            @opener.open(@indexfile,"r") do |f|
              until f.eof?
                # read the entry
                entry = read_entry(f, n)
                n += 1
              end
            end
            return true
          rescue Errno::ENOENT
            return false
          end
        end
        
        ##
        # Packs up the revision entry for writing to the binary file.
        # 
        # @param [IndexEntry] entry this is the entry that has to be formatted
        #   into binary.
        # @param [Fixnum] rev this is the index number of the entry - if it's
        #   the first revision (rev == 0) then we treat it slightly differently.
        # @return [String] the entry converted into binary suitable for writing.
        def pack_entry(entry, rev)
          entry = IndexEntry.new(*entry) if entry.kind_of? Array
          p = entry.to_s
          if rev == 0 || rev == 1
            p = [version].pack(VERSION_FORMAT) + p[4..-1] # initial entry
          end
          p
        end
        
        ##
        # This method writes the index to file. Pretty 1337h4><.
        #
        # @param [String] index_file the path to the index file.
        # @param [IndexEntry] entry the entry to append to the index
        # @param [Journal] journal a journal to log our actions to. Used for
        #   error recovery.
        # @param [Hash{Symbol => String}] data the data to write corresponding to
        #   this entry. Keys:
        #   :compression => The type of compression to use. One letter, such as
        #     "u" for uncompressed 
        #   :text => the text that makes up the revision data
        # @param [IO] index_file_handle a possibly re-usable index file handle to use
        #   for writing. used to limit file opens/closes.
        def write_entry(index_file, entry, journal, data, index_file_handle = nil)
          curr = self.size - 1
          
          link = entry.link_rev
          data_file = index_file[0..-3] + ".d"
          
          entry = pack_entry entry, link
          
          @opener.open(data_file, "a+") do |data_file_handle|
            data_offset = data_file_handle.tell
            
            data_file_handle.write data[:compression] if data[:compression].any?
            data_file_handle.write data[:text]
            data_file_handle.flush
            
            journal << {:file => data_file, :offset => data_offset, :data => curr}
          end
          
          index_file_handle ||= (opened = true && @opener.open(index_file, "a+"))
          
          offset = index_file_handle.tell
          index_file_handle.write entry
          index_file_handle.close if opened
          
          journal << {:file => index_file, :offset => offset, :data => curr}
        end
    
        def fix_first_entry!
          first_entry = self[0]
          type = Index.get_version(first_entry.offset_flags)
          first_entry.true_offset = 0
          first_entry.flags = type
          @index[0] = first_entry
        end
      
      end
      
      ##
      # = LazyIndex
      # When this gets filled in, this class will let us access an index without loading
      # every entry first. This is handy because index files can get pretty fuckin big.
      #
      # Only handles non-inline, big files.
      #
      # My strategy is going to be this: fill in the node_map to start with, but when they
      # call [], fill in @index selectively by jumping to the appropriate place in the
      # open file, and reading then.
      class LazyIndex < IndexVersionNG
        ##
        # Initializes the lazy index.  Keeps a persistent open file handle... this might
        # have to be reverted later.
        def initialize(opener, inputfile)
          @opener = opener
          @indexfile = inputfile
          @cache = nil
          @index = []
          @node_map = {Node::NULL_ID => Node::NULL_REV}
          
          @index_handle = @opener.open(inputfile, "r")
          max_entry = File.size(@opener.join(inputfile)) / BLOCK_SIZE
          read_all_node_ids!
          fix_first_entry!
          
          @index[max_entry] = IndexEntry.new(0,0,0,-1,-1,-1,-1,Node::NULL_ID)
        end
        
        ##
        # Reads in an index entry from an IO source. Extra lazy!
        #
        # @param [IO] input the input, IO source.
        # @param [Integer] num the number of the entry
        # @return [IndexEntry] the parsed entry
        def read_entry(input, num)
          IndexEntry.new(input).fix_signs
        end
        
        def read_all_node_ids!
          idx = 0
          @index_handle.seek(SHA1_OFFSET, IO::SEEK_SET)
          until @index_handle.eof?
            @node_map[@index_handle.read(20)] = idx
            @index_handle.seek(BLOCK_SIZE - 20, IO::SEEK_CUR)
            idx += 1
          end
          @index_handle.rewind
        end
        
        ##
        # Gets the entry at the given revision index. This requires a bit more logic because
        # our index isn't actually loaded.
        #
        # @param [Integer, Range] idx the revision number of the desired index entry
        # @return [IndexEntry] the entry at the requested location in the index
        def [](idx)
          if idx.is_a?(Range)
            return @index[idx].each_with_index.map {|val, idx| force_load(idx)}
          end
          # idx is an index now
          force_load(idx)
        end
        
        ##
        # Iterates over each entry in the index, including the null revision
        def each(&b)
          # force loading of the full listing by using self[]
          self[0..(@index.size - 1)].each(&b)
        end
        
        ##
        # Forces the loading of the given revision number.
        #
        # @param [Fixnum] idx the index to load manually
        # @return [IndexEntry] the loaded entry
        def force_load(idx)
          return @index[idx] if @index[idx]
          @index_handle.seek(idx * BLOCK_SIZE)
          @index[idx] = read_entry(@index_handle, idx)
        end
        
        ##
        # Closes the active index handle.
        def close
          @index_handle.close
        end
      end
      
      ##
      # = IndexInlineNG
      # This is a variant of the current version of the index format, in which the data
      # is stored in the actual index file itself, right after the little revision
      # entry block (see {IndexEntry}). This means less IO, which is good.
      #
      class IndexInlineNG < IndexVersionNG
        def inline?; true; end
        def version; super | REVLOG_NG_INLINE_DATA; end
        
        ##
        # @todo "not sure what the 0 is for yet or i'd make this a hash" (see code)
        # This method overrides the parent class' method that reads entries sequentially
        # from the index file. Each entry is followed by the data for that revision
        # so we have to skip over that data for our purposes.
        def parse_file
          n = offset = 0
          begin
            @opener.open(@indexfile,"r") do |f|
              until f.eof?
                # read 1 entry
                entry = read_entry(f, n)
                n += 1
                break if entry.compressed_len < 0
                
                # skip past the data, too!
                f.seek(entry.compressed_len, IO::SEEK_CUR)
              end
            end
            return true
          rescue Errno::ENOENT
            return false
          end
        end
        
        ##
        # This method writes the index entry to file. Pretty 1337h4><.
        #
        # @param [String] index_file the path to the index file.
        # @param [IndexEntry] entry the entry to append to the index
        # @param [Journal] journal a journal to log our actions to. Used for
        #   error recovery.
        # @param [Hash{Symbol => String}] data the data to write corresponding to
        #   this entry. Keys:
        #   :compression => The type of compression to use. One letter, such as
        #     "u" for uncompressed 
        #   :text => the text that makes up the revision data
        # @param [IO] index_file_handle a possibly re-usable index file handle to use
        #   for writing. used to limit file opens/closes.
        def write_entry(index_file, entry, journal, data, index_file_handle = nil)
          curr, prev = self.size - 1, self.size - 2
          
          link = entry.link_rev
          entry = pack_entry entry, curr
          
          index_file_handle ||= (opened = true && @opener.open(index_file, "a+"))
          
          offset = index_file_handle.tell
          
          index_file_handle.write entry
          index_file_handle.write data[:compression] if data[:compression].any?
          index_file_handle.write data[:text]
          
          index_file_handle.close if opened
          
          journal << {:file => index_file, :offset => offset, :data => curr}
          
        end
        
      end
    end
  end
end
