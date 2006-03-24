#!/usr/local/bin/ruby -w

# = faster_csv.rb -- Faster CSV Reading and Writing
#
#  Created by James Edward Gray II on 2005-10-31.
#  Copyright 2005 Gray Productions. All rights reserved.
# 
# See FasterCSV for documentation.

require "forwardable"
require "English"
require "enumerator"
require "date"
require "stringio"

# 
# This class provides a complete interface to CSV files and data.  It offers
# tools to enable you to read and write to and from Strings or IO objects, as
# needed.
# 
# == Reading
# 
# === From a File
# 
# ==== A Line at a Time
# 
#   FasterCSV.foreach("path/to/file.csv") do |row|
#     # use row here...
#   end
# 
# ==== All at Once
# 
#   arr_of_arrs = FasterCSV.read("path/to/file.csv")
# 
# === From a String
# 
# ==== A Line at a Time
# 
#   FasterCSV.parse("CSV,data,String") do |row|
#     # use row here...
#   end
# 
# ==== All at Once
# 
#   arr_of_arrs = FasterCSV.parse("CSV,data,String")
# 
# == Writing
# 
# === To a File
# 
#   FasterCSV.open("path/to/file.csv", "w") do |csv|
#     csv << ["row", "of", "CSV", "data"]
#     csv << ["another", "row"]
#     # ...
#   end
# 
# === To a String
# 
#   csv_string = FasterCSV.generate do |csv|
#     csv << ["row", "of", "CSV", "data"]
#     csv << ["another", "row"]
#     # ...
#   end
# 
# == Convert a Single Line
# 
#   csv_string = ["CSV", "data"].to_csv   # to CSV
#   csv_array  = "CSV,String".parse_csv   # from CSV
# 
class FasterCSV
  # The version of the installed library.
  VERSION = "0.2.0".freeze
  
  # 
  # A FasterCSV::Row is part Array and part Hash.  It retains an order for the
  # fields and allows duplicates just as an Array would, but also allows you to
  # access fields by name just as you could if they were in a Hash.
  # 
  # All rows returned by FasterCSV will be constructed from this class, if
  # header row processing is activated.
  # 
  class Row
    # 
    # Construct a new FasterCSV::Row from +headers+ and +fields+, which are
    # expected to be Arrays.  If one Array is shorter than the other, it will be
    # padded with +nil+ objects.
    # 
    # The optional +header_row+ parameter can be set to +true+ to indicate, via
    # FasterCSV::Row.header_row?() and FasterCSV::Row.field_row?(), that this is
    # a header row.  Otherwise, the row is assumes to be a field row.
    # 
    def initialize( headers, fields, header_row = false )
      @header_row = header_row
      
      # handle extra headers or fields
      @row = if headers.size > fields.size
        headers.zip(fields)
      else
        fields.zip(headers).map { |pair| pair.reverse }
      end
    end
    
    # Returns +true+ if this is a header row.
    def header_row?
      @header_row
    end
    
    # Returns +true+ if this is a field row.
    def field_row?
      not header_row?
    end
    
    # Returns the headers of this row.
    def headers
      @row.map { |pair| pair.first }
    end
    
    # 
    # :call-seq:
    #   field( header )
    #   field( header, offset )
    #   field( index )
    # 
    # This method will fetch the field value by +header+ or +index+.  If a field
    # is not found, +nil+ is returned.
    # 
    # When provided, +offset+ ensures that a header match occurrs on or later
    # than the +offset+ index.  You can use this to find duplicate headers, 
    # without resorting to hard-coding exact indices.
    # 
    def field( header_or_index, minimum_index = 0 )
      # locate the pair
      finder = header_or_index.is_a?(Integer) ? :[] : :assoc
      pair   = @row[minimum_index..-1].send(finder, header_or_index)

      # return the field if we have a pair
      pair.nil? ? nil : pair.last
    end
    alias_method :[], :field
    
    # 
    # :call-seq:
    #   []=( header, value )
    #   []=( header, offset, value )
    #   []=( index, value )
    # 
    # Looks up the field by the semantics described in FasterCSV::Row.field()
    # and assigns the +value+.
    # 
    # Assigning past the end of the row with an index will set all pairs between
    # to <tt>[nil, nil]</tt>.  Assigning to an unused header appends the new
    # pair.
    # 
    def []=( *args )
      value = args.pop
      
      if args.first.is_a? Integer
        if @row[args.first].nil?  # extending past the end with index
          @row[args.first] = [nil, value]
          @row.map! { |pair| pair.nil? ? [nil, nil] : pair }
        else                      # normal index assignment
          @row[args.first][1] = value
        end
      else
        index = index(*args)
        if index.nil?             # appending a field
          self << [args.first, value]
        else                      # normal header assignment
          @row[index][1] = value
        end
      end
    end
    
    # 
    # :call-seq:
    #   <<( field )
    #   <<( header_and_field_array )
    #   <<( header_and_field_hash )
    # 
    # If a two-element Array is provided, it is assumed to be a header and field
    # and the pair is appended.  A Hash works the same way with the key being
    # the header and the value being the field.  Anything else is assumed to be
    # a lone field which is appended with a +nil+ header.
    # 
    # This method returns the row for chaining.
    # 
    def <<( arg )
      if arg.is_a?(Array) and arg.size == 2  # appending a header and name
        @row << arg
      elsif arg.is_a?(Hash)                  # append header and name pairs
        arg.each { |pair| @row << pair }
      else                                   # append field value
        @row << [nil, arg]
      end
      
      self  # for chaining
    end
    
    # 
    # A shortcut for appending multiple fields.  Equivalent to:
    # 
    #   args.each { |arg| faster_csv_row << arg }
    # 
    # This method returns the row for chaining.
    # 
    def push( *args )
      args.each { |arg| self << arg }
      
      self  # for chaining
    end
    
    # 
    # :call-seq:
    #   delete( header )
    #   delete( header, offset )
    #   delete( index )
    # 
    # Used to remove a pair from the row by +header+ or +index+.  The pair is
    # located as described in FasterCSV::Row.field().  The deleted pair is 
    # returned, or +nil+ if a pair could not be found.
    # 
    def delete( header_or_index, minimum_index = 0 )
      if header_or_index.is_a? Integer  # by index
        @row.delete_at(header_or_index)
      else                              # by header
        @row.delete_at(index(header_or_index, minimum_index))
      end
    end
    
    # 
    # The provided +block+ is passed a header and field for each pair in the row
    # and expected to return +true+ or +false+, depending on whether the pair
    # should be deleted.
    # 
    # This method returns the row for chaining.
    # 
    def delete_if( &block )
      @row.delete_if(&block)
      
      self  # for chaining
    end
    
    # 
    # This method accepts any number of arguments which can be headers, indices,
    # or two-element Arrays containing a header and offset.  Each argument will
    # be replaced with a field lookup as described in FasterCSV::Row.field().
    # 
    # If called with no arguments, all fields are returned.
    # 
    def fields( *headers_and_or_indices )
      if headers_and_or_indices.empty?  # return all fields--no arguments
        @row.map { |pair| pair.last }
      else                              # or work like values_at()
        headers_and_or_indices.map { |h_or_i| field(*Array(h_or_i)) }
      end
    end
    alias_method :values_at, :fields
    
    # 
    # :call-seq:
    #   index( header )
    #   index( header, offset )
    # 
    # This method will return the index of a field with the provided +header+.
    # The +offset+ can be used to locate duplicate header names, as described in
    # FasterCSV::Row.field().
    # 
    def index( header, minimum_index = 0 )
      # find the pair
      index = headers[minimum_index..-1].index(header)
      # return the index at the right offset, if we found one
      index.nil? ? nil : index + minimum_index
    end
    
    # Returns +true+ if +name+ is a header for this row, and +false+ otherwise.
    def header?( name )
      headers.include? name
    end
    alias_method :include?, :header?
    
    # 
    # Returns +true+ if +data+ matches a field in this row, and +false+
    # otherwise.
    # 
    def field?( data )
      fields.include? data
    end

    include Enumerable
    
    # 
    # Yields each pair of the row as header and field tuples (much like
    # iterating over a Hash).
    # 
    # Support for Enumerable.
    # 
    # This method returns the row for chaining.
    # 
    def each( &block )
      @row.each(&block)
      
      self  # for chaining
    end
    
    # 
    # Collapses the row into a simple Hash.  Be warning that this discards field
    # order and clobbers duplicate fields.
    # 
    def to_hash
      # flatten just one level of the internal Array
      Hash[*@row.inject(Array.new) { |ary, pair| ary.push(*pair) }]
    end
    
    # 
    # Returns the row as a CSV String.  Headers are not used.  Equivalent to:
    # 
    #   faster_csv_row.fields.to_csv( options )
    # 
    def to_csv( options = Hash.new )
      fields.to_csv(options)
    end
    alias_method :to_s, :to_csv
  end

  # The error thrown when the parser encounters illegal CSV formatting.
  class MalformedCSVError < RuntimeError; end
  
  # 
  # A FieldInfo Struct contains details about a field's position in the data
  # source it was read from.  FasterCSV will pass this Struct to some blocks
  # that make decisions based on field structure.  See 
  # FasterCSV.convert_fields() for an example.
  # 
  # <b><tt>index</tt></b>::  The zero-based index of the field in its row.
  # <b><tt>line</tt></b>::   The line of the data source this row is from.
  # 
  FieldInfo = Struct.new(:index, :line)
  
  # 
  # This Hash holds the built-in converters of FasterCSV that can be accessed by
  # name.  You can select Converters with FasterCSV.convert() or through the
  # +options+ Hash passed to FasterCSV::new().
  # 
  # <b><tt>:integer</tt></b>::    Converts any field Integer() accepts.
  # <b><tt>:float</tt></b>::      Converts any field Float() accepts.
  # <b><tt>:numeric</tt></b>::    A combination of <tt>:integer</tt> 
  #                               and <tt>:float</tt>.
  # <b><tt>:date</tt></b>::       Converts any field Date::parse() accepts.
  # <b><tt>:date_time</tt></b>::  Converts any field DateTime::parse() accepts.
  # <b><tt>:all</tt></b>::        All built-in converters.  A combination of 
  #                               <tt>:date_time</tt> and <tt>:numeric</tt>.
  # 
  # This Hash is intetionally left unfrozen and users should feel free to add
  # values to it that can be accessed by all FasterCSV objects.
  # 
  # To add a combo field, the value should be an Array of names.  Combo fields
  # can be nested with other combo fields.
  # 
  Converters = { :integer   => lambda { |f| Integer(f)        rescue f },
                 :float     => lambda { |f| Float(f)          rescue f },
                 :numeric   => [:integer, :float],
                 :date      => lambda { |f| Date.parse(f)     rescue f },
                 :date_time => lambda { |f| DateTime.parse(f) rescue f },
                 :all       => [:date_time, :numeric] }

  # 
  # This Hash holds the built-in header converters of FasterCSV that can be
  # accessed by name.  You can select HeaderConverters with
  # FasterCSV.header_convert() or through the +options+ Hash passed to
  # FasterCSV::new().
  # 
  # <b><tt>:downcase</tt></b>::  Calls downcase() on the header String.
  # <b><tt>:symbol</tt></b>::    The header String is downcased, spaces are
  #                              replaced with underscores, non-word characters
  #                              are dropped, and finally to_sym() is called.
  # 
  # This Hash is intetionally left unfrozen and users should feel free to add
  # values to it that can be accessed by all FasterCSV objects.
  # 
  # To add a combo field, the value should be an Array of names.  Combo fields
  # can be nested with other combo fields.
  # 
  HeaderConverters = {
    :downcase => lambda { |h| h.downcase },
    :symbol   => lambda { |h|
      h.downcase.tr(" ", "_").delete("^a-z0-9_").to_sym
    }
  }
  
  # 
  # The options used when no overrides are given by calling code.  They are:
  # 
  # <b><tt>:col_sep</tt></b>::            <tt>","</tt>
  # <b><tt>:row_sep</tt></b>::            <tt>:auto</tt>
  # <b><tt>:converters</tt></b>::         +nil+
  # <b><tt>:headers</tt></b>::            +false+
  # <b><tt>:return_headers</tt></b>::     +false+
  # <b><tt>:header_converters</tt></b>::  +nil+
  # 
  DEFAULT_OPTIONS = { :col_sep           => ",",
                      :row_sep           => :auto,
                      :converters        => nil,
                      :headers           => false,
                      :return_headers    => false,
                      :header_converters => nil }.freeze
  
  # 
  # :call-seq:
  #   filter( options = Hash.new ) { |row| ... }
  #   filter( input, options = Hash.new ) { |row| ... }
  #   filter( input, output, options = Hash.new ) { |row| ... }
  # 
  # This method is a convenience for building Unix-like filters for CSV data.
  # Each row is yielded to the provided block which can alter it as needed.  
  # After the block returns, the row is appended to +output+ altered or not.
  # 
  # The +input+ and +output+ arguments can be anything FasterCSV::new() accepts
  # (generally String or IO objects).  If not given, they default to 
  # <tt>ARGF</tt> and <tt>STDOUT</tt>.
  # 
  # The +options+ parameter is also filtered down to FasterCSV::new() after some
  # clever key parsing.  Any key beginning with <tt>:in_</tt> or 
  # <tt>:input_</tt> will have that leading identifier stripped and will only
  # be used in the +options+ Hash for the +input+ object.  Keys starting with
  # <tt>:out_</tt> or <tt>:output_</tt> affect only +output+.  All other keys 
  # are assigned to both objects.
  # 
  # The <tt>:output_row_sep</tt> +option+ defaults to
  # <tt>$INPUT_RECORD_SEPARATOR</tt> (<tt>$/</tt>).
  # 
  def self.filter( *args )
    # parse options for input, output, or both
    in_options, out_options = Hash.new, {:row_sep => $INPUT_RECORD_SEPARATOR}
    if args.last.is_a? Hash
      args.pop.each do |key, value|
        case key.to_s
        when /\Ain(?:put)?_(.+)\Z/
          in_options[$1.to_sym] = value
        when /\Aout(?:put)?_(.+)\Z/
          out_options[$1.to_sym] = value
        else
          in_options[key]  = value
          out_options[key] = value
        end
      end
    end
    # build input and output wrappers
    input   = FasterCSV.new(args.shift || ARGF,   in_options)
    output  = FasterCSV.new(args.shift || STDOUT, out_options)
    
    # read, yield, write
    input.each do |row|
      yield row
      output << row
    end
  end
  
  # 
  # This method is intended as the primary interface for reading CSV files.  You
  # pass a +path+ and any +options+ you wish to set for the read.  Each row of
  # file will be passed to the provided +block+ in turn.
  # 
  # The +options+ parameter can be anthing FasterCSV::new() understands.
  # 
  def self.foreach( path, options = Hash.new, &block )
    open(path, options) do |csv|
      csv.each(&block)
    end
  end

  # 
  # :call-seq:
  #   generate( str, options = Hash.new ) { |faster_csv| ... }
  #   generate( options = Hash.new ) { |faster_csv| ... }
  # 
  # This method wraps a String you provide, or an empty default String, in a 
  # FasterCSV object which is passed to the provided block.  You can use the 
  # block to append CSV rows to the String and when the block exits, the 
  # final String will be returned.
  # 
  # Note that a passed String *is* modfied by this method.  Call dup() before
  # passing if you need a new String.
  # 
  # The +options+ parameter can be anthing FasterCSV::new() understands.
  # 
  def self.generate( *args )
    # add a default empty String, if none was given
    if args.first.is_a? String
      io = StringIO.new(args.shift)
      io.seek(0, IO::SEEK_END)
      args.unshift(io)
    else
      args.unshift("")
    end
    faster_csv = new(*args)  # wrap
    yield faster_csv         # yield for appending
    faster_csv.string        # return final String
  end

  # 
  # This method is a shortcut for converting a single row (Array) into a CSV 
  # String.
  # 
  # The +options+ parameter can be anthing FasterCSV::new() understands.
  # 
  # The <tt>:row_sep</tt> +option+ defaults to <tt>$INPUT_RECORD_SEPARATOR</tt>
  # (<tt>$/</tt>) when calling this method.
  # 
  def self.generate_line( row, options = Hash.new )
    options = {:row_sep => $INPUT_RECORD_SEPARATOR}.merge(options)
    (new("", options) << row).string
  end
  
  # 
  # :call-seq:
  #   open( filename, mode="r", options = Hash.new ) { |faster_csv| ... }
  #   open( filename, mode="r", options = Hash.new )
  # 
  # This method opens an IO object, and wraps that with FasterCSV.  This is
  # intended as the primary interface for writing a CSV file.
  # 
  # You may pass any +args+ Ruby's open() understands followed by an optional
  # Hash containing any +options+ FasterCSV::new() understands.
  # 
  # This method works like Ruby's open() call, in that it will pass a FasterCSV
  # object to a provided block and close it when the block termminates, or it
  # will return the FasterCSV object when no block is provided.  (*Note*: This
  # is different from the standard CSV library which passes rows to the block.  
  # Use FasterCSV::foreach() for that behavior.)
  # 
  # An opened FasterCSV object will delegate to many IO methods, for 
  # convenience.  You may call:
  # 
  # * binmode()
  # * close()
  # * close_read()
  # * close_write()
  # * closed?()
  # * eof()
  # * eof?()
  # * fcntl()
  # * fileno()
  # * flush()
  # * fsync()
  # * ioctl()
  # * isatty()
  # * lineno()
  # * pid()
  # * pos()
  # * reopen()
  # * rewind()
  # * seek()
  # * stat()
  # * sync()
  # * sync=()
  # * tell()
  # * to_i()
  # * to_io()
  # * tty?()
  # 
  def self.open( *args )
    # find the +options+ Hash
    options = if args.last.is_a? Hash then args.pop else Hash.new end
    # wrap a File opened with the remaining +args+
    csv     = new(File.open(*args), options)
    
    # handle blocks like Ruby's open(), not like the CSV library
    if block_given?
      begin
        yield csv
      ensure
        csv.close
      end
    else
      csv
    end
  end
  
  # 
  # :call-seq:
  #   parse( str, options = Hash.new ) { |row| ... }
  #   parse( str, options = Hash.new )
  # 
  # This method can be used to easily parse CSV out of a String.  You may either
  # provide a +block+ which will be called with each row of the String in turn,
  # or just use the returned Array of Arrays (when no +block+ is given).
  # 
  # You pass your +str+ to read from, and an optional +options+ Hash containing
  # anything FasterCSV::new() understands.
  # 
  def self.parse( *args, &block )
    csv = new(*args)
    if block.nil?  # slurp contents, if no block is given
      begin
        csv.read
      ensure
        csv.close
      end
    else           # or pass each row to a provided block
      csv.each(&block)
    end
  end
  
  # 
  # This method is a shortcut for converting a single line of a CSV String into 
  # a into an Array.  Note that if +line+ contains multiple rows, anything 
  # beyond the first row is ignored.
  # 
  # The +options+ parameter can be anthing FasterCSV::new() understands.
  # 
  def self.parse_line( line, options = Hash.new )
    new(line, options).shift
  end
  
  # 
  # Use to slurp a CSV file into an Array of Arrays.  Pass the +path+ to the 
  # file and any +options+ FasterCSV::new() understands.
  # 
  def self.read( path, options = Hash.new )
    open(path, options) { |csv| csv.read }
  end
  
  # Alias for FasterCSV::read().
  def self.readlines( *args )
    read(*args)
  end
  
  # 
  # This constructor will wrap either a String or IO object passed in +data+ for
  # reading and/or writing.  In addition to the FasterCSV instance methods, 
  # several IO methods are delegated.  (See FasterCSV::open() for a complete 
  # list.)  If you pass a String for +data+, you can later retrieve it (after
  # writing to it, for example) with FasterCSV.string().
  # 
  # Note that a wrapped String will be positioned at at the beginning (for 
  # reading).  If you want it at the end (for writing), use 
  # FasterCSV::generate().  If you want any other positioning, pass a preset 
  # StringIO object instead.
  # 
  # You may set any reading and/or writing preferences in the +options+ Hash.  
  # Available options are:
  # 
  # <b><tt>:col_sep</tt></b>::            The String placed between each field.
  # <b><tt>:row_sep</tt></b>::            The String appended to the end of each
  #                                       row.  This can be set to the special
  #                                       <tt>:auto</tt> setting, which requests
  #                                       that FasterCSV automatically discover
  #                                       this from the data.  Auto-discovery
  #                                       reads ahead in the data looking for
  #                                       the next <tt>"\r\n"</tt>,
  #                                       <tt>"\n"</tt>, or <tt>"\r"</tt>
  #                                       sequence.  A sequence will be selected
  #                                       even if it occurs in a quoted field,
  #                                       assuming that you would have the same
  #                                       line endings there.  If none of those
  #                                       sequences is found, +data+ is
  #                                       <tt>ARGF</tt>, <tt>STDIN</tt>,
  #                                       <tt>STDOUT</tt>, or <tt>STDERR</tt>,
  #                                       or the stream is only available for
  #                                       output, the default
  #                                       <tt>$INPUT_RECORD_SEPARATOR</tt>
  #                                       (<tt>$/</tt>) is used.  Obviously,
  #                                       discovery takes a little time.  Set
  #                                       manually if speed is important.
  # <b><tt>:converters</tt></b>::         An Array of names from the Converters
  #                                       Hash and/or lambdas that handle custom
  #                                       conversion.  A single converter
  #                                       doesn't have to be in an Array.
  # <b><tt>:headers</tt></b>::            If set to <tt>:first_row</tt> or 
  #                                       +true+, the initial row of the CSV
  #                                       file will be treated as a row of
  #                                       headers.  This setting causes
  #                                       FasterCSV.shift() to return rows as
  #                                       FasterCSV::Row objects instead of
  #                                       Arrays.
  # <b><tt>:return_headers</tt></b>::     When +false+, header rows are silently
  #                                       swallowed.  If set to +true+, header
  #                                       rows are returned in a FasterCSV::Row
  #                                       object with identical headers and
  #                                       fields (save that the fields do not go
  #                                       through the converters).
  # <b><tt>:header_converters</tt></b>::  Identical in functionality to
  #                                       <tt>:converters</tt> save that the
  #                                       conversions are only made to header
  #                                       rows.
  # 
  # See FasterCSV::DEFAULT_OPTIONS for the default settings.
  # 
  # Options cannot be overriden in the instance methods for performance reasons,
  # so be sure to set what you want here.
  # 
  def initialize( data, options = Hash.new )
    # build the options for this read/write
    options = DEFAULT_OPTIONS.merge(options)
    
    # create the IO object we will read from
    @io = if data.is_a? String then StringIO.new(data) else data end
    
    init_separators(options)
    init_parsers(options)
    init_converters(options)
    init_headers(options)
    
    unless options.empty?
      raise ArgumentError, "Unknown options:  #{options.keys.join(', ')}."
    end
  end
  
  ### IO and StringIO Delegation ###
  
  extend Forwardable
  def_delegators :@io, :binmode, :close, :close_read, :close_write, :closed?,
                       :eof, :eof?, :fcntl, :fileno, :flush, :fsync, :ioctl,
                       :isatty, :lineno, :pid, :pos, :reopen, :rewind, :seek,
                       :stat, :string, :sync, :sync=, :tell, :to_i, :to_io,
                       :tty?

  ### End Delegation ###
  
  # 
  # The primary write method for wrapped Strings and IOs, +row+ (an Array or
  # FasterCSV::Row) is converted to CSV and appended to the data source.  When a
  # FasterCSV::Row is passed, only the row's fields() are appended to the
  # output.
  # 
  # The data source must be open for writing.
  # 
  def <<( row )
    # handle FasterCSV::Row objects
    row = row.fields if row.is_a? self.class::Row
    
    @io << row.map do |field|
      if field.nil?  # reverse +nil+ fields as empty unquoted fields
        ""
      else
        field = String(field)  # Stringify fields
        # reverse empty fields as empty quoted fields
        if field.empty? or field.count(%Q{\r\n#{@col_sep}"}).nonzero?
          %Q{"#{field.gsub('"', '""')}"}  # escape quoted fields
        else
          field  # unquoted field
        end
      end
    end.join(@col_sep) + @row_sep  # add separators
    
    self  # for chaining
  end
  alias_method :add_row, :<<
  alias_method :puts,    :<<
  
  # 
  # :call-seq:
  #   convert( name )
  #   convert { |field| ... }
  #   convert { |field, field_info| ... }
  # 
  # You can use this method to install a FasterCSV::Converters built-in, or 
  # provide a block that handles a custom conversion.
  # 
  # If you provide a block that takes one argument, it will be passed the field
  # and is expected to return the converted value or the field itself.  If your
  # block takes two arguments, it will also be passed a FieldInfo Struct, 
  # containing details about the field.  Again, the block should return a 
  # converted field or the field itself.
  # 
  def convert( name = nil, &converter )
    add_converter(:converters, self.class::Converters, name, &converter)
  end

  # 
  # :call-seq:
  #   header_convert( name )
  #   header_convert { |field| ... }
  #   header_convert { |field, field_info| ... }
  # 
  # Identical to FasterCSV.convert(), but for header rows.
  # 
  # Note that this method must be called before header rows are read to have any
  # effect.
  # 
  def header_convert( name = nil, &converter )
    add_converter( :header_converters,
                   self.class::HeaderConverters,
                   name,
                   &converter )
  end
  
  include Enumerable
  
  # 
  # Yields each row of the data source in turn.
  # 
  # Support for Enumerable.
  # 
  # The data source must be open for reading.
  # 
  def each
    while row = shift
      yield row
    end
  end
  
  # 
  # Slurps the remaining rows and returns an Array of Arrays.
  # 
  # The data source must be open for reading.
  # 
  def read
    to_a
  end
  alias_method :readlines, :read
  
  # Returns +true+ if the next row read will be a header row.
  def header_row?
    @use_headers and @headers.nil?
  end
  
  # 
  # The primary read method for wrapped Strings and IOs, a single row is pulled
  # from the data source, parsed and returned as an Array of fields (if header
  # rows are not used) or a FasterCSV::Row (when header rows are used).
  # 
  # The data source must be open for reading.
  # 
  def shift
    # begin with a blank line, so we can always add to it
    line = ""

    # 
    # it can take multiple calls to <tt>@io.gets()</tt> to get a full line,
    # because of \r and/or \n characters embedded in quoted fields
    # 
    loop do
      # add another read to the line
      line  += @io.gets(@row_sep) rescue return nil
      # copy the line so we can chop it up in parsing
      parse = line.dup
      parse.sub!(@parsers[:line_end], "")
      
      # 
      # I believe a blank line should be an <tt>Array.new</tt>, not 
      # CSV's <tt>[nil]</tt>
      # 
      return Array.new if parse.empty?

      # 
      # shave leading empty fields if needed, because the main parser chokes 
      # on these
      # 
      csv = if parse.sub!(@parsers[:leading_fields], "")
        [nil] * $&.length
      else
        Array.new
      end
      # 
      # then parse the main fields with a hyper-tuned Regexp from 
      # Mastering Regular Expressions, Second Edition
      # 
      parse.gsub!(@parsers[:csv_row]) do
        csv << if $1.nil?     # we found an unquoted field
          if $2.empty?        # switch empty unquoted fields to +nil+...
            nil               # for CSV compatibility
          else
            # I decided to take a strict approach to CSV parsing...
            if $2.count("\r\n").zero?  # verify correctness of field...
              $2
            else
              # or throw an Exception
              raise MalformedCSVError, 'Unquoted fields do not allow \r or \n.'
            end
          end
        else                  # we found a quoted field...
          $1.gsub('""', '"')  # unescape contents
        end
        ""  # gsub!'s replacement, clear the field
      end

      # if parse is empty?(), we found all the fields on the line...
      if parse.empty?
        # convert fields if needed...
        csv = convert_fields(csv) unless header_row? or @converters.empty?
        # parse out header rows and handle FasterCSV::Row conversions...
        csv = parse_headers(csv)  if     @use_headers
        # return the results
        break csv
      end
      # if we're not empty?() but at eof?(), a quoted field wasn't closed...
      raise MalformedCSVError, "Unclosed quoted field." if @io.eof?
      # otherwise, we need to loop and pull some more data to complete the row
    end
  end
  alias_method :gets,     :shift
  alias_method :readline, :shift
  
  private
  
  # 
  # Stores the indicated separators for later use.
  # 
  # If auto-discovery was requested for <tt>@row_sep</tt>, this method will read
  # ahead in the <tt>@io</tt> and try to find one.  <tt>ARGF</tt>,
  # <tt>STDIN</tt>, <tt>STDOUT</tt>, <tt>STDERR</tt> and any stream open for
  # output only with a default <tt>@row_sep</tt> of
  # <tt>$INPUT_RECORD_SEPARATOR</tt> (<tt>$/</tt>).
  # 
  def init_separators( options )
    # store the selected separators
    @col_sep = options.delete(:col_sep)
    @row_sep = options.delete(:row_sep)
    
    # automatically discover row separator when requested
    if @row_sep == :auto
      if [ARGF, STDIN, STDOUT, STDERR].include? @io
        @row_sep = $INPUT_RECORD_SEPARATOR
      else
        begin
          saved_pos = @io.pos  # remember where we were
          while @row_sep == :auto
            # 
            # if we run out of data, it's probably a single line 
            # (use a sensible default)
            # 
            if @io.eof?
              @row_sep = $INPUT_RECORD_SEPARATOR
              break
            end
      
            # read ahead a bit
            sample =  @io.read(1024)
            sample += @io.read(1) if sample[-1..-1] == "\r" and not @io.eof?
      
            # try to find a standard separator
            if sample =~ /\r\n?|\n/
              @row_sep = $&
              break
            end
          end
          @io.seek(saved_pos)  # reset back to the remembered position 
        rescue IOError  # stream not opened for reading
          @row_sep = $INPUT_RECORD_SEPARATOR
        end
      end
    end
  end
  
  # Pre-compiles parsers and stores them by name for access during reads.
  def init_parsers( options )
    # prebuild Regexps for faster parsing
    @parsers    = {
      :leading_fields =>
        /\A#{Regexp.escape(@col_sep)}+/,         # for empty leading fields
      :csv_row        =>
        ### The Primary Parser ###
        / \G(?:^|#{Regexp.escape(@col_sep)})     # anchor the match
          (?: "((?>[^"]*)(?>""[^"]*)*)"          # find quoted fields
              |                                  # ... or ...
              ([^"#{Regexp.escape(@col_sep)}]*)  # unquoted fields
              )/x,
        ### End Primary Parser ###
      :line_end       =>
        /#{Regexp.escape(@row_sep)}\Z/           # safer than chomp!()
    }
  end
  
  # 
  # Loads any converters requested during construction.
  # 
  # If +field_name+ is set <tt>:converters</tt> (the default) field converters
  # are set.  When +field_name+ is <tt>:header_converters</tt> header converters
  # are added instead.
  # 
  def init_converters( options, field_name = :converters )
    instance_variable_set("@#{field_name}", Array.new)
    
    # find the correct method to add the coverters
    convert = method(field_name.to_s.sub(/ers\Z/, ""))
    
    # load converters
    unless options[field_name].nil?
      # allow a single converter not wrapped in an Array
      unless options[field_name].is_a? Array
        options[field_name] = [options[field_name]]
      end
      # load each converter...
      options[field_name].each do |converter|
        if converter.is_a? Proc  # custom code block
          convert.call(&converter)
        else                     # by name
          convert.call(converter)
        end
      end
    end
    
    options.delete(field_name)
  end
  
  # Stores header row settings and loads header converters, if needed.
  def init_headers( options )
    @use_headers    = options.delete(:headers)
    @return_headers = options.delete(:return_headers)

    @headers = nil
    
    init_converters(options, :header_converters)
  end
  
  # 
  # The actual work method for adding converters, used by both 
  # FasterCSV.convert() and FasterCSV.header_convert().
  # 
  # This method requires the +var_name+ of the instance variable to place the
  # converters in, the +const+ Hash to lookup named converters in, and the
  # normal parameters of the FasterCSV.convert() and FasterCSV.header_convert()
  # methods.
  # 
  def add_converter( var_name, const, name = nil, &converter )
    if name.nil?  # custom converter
      instance_variable_get("@#{var_name}") << converter
    else          # named converter
      combo = const[name]
      case combo
      when Array  # combo converter
        combo.each do |converter_name|
          add_converter(var_name, const, converter_name)
        end
      else        # individual named converter
        instance_variable_get("@#{var_name}") << combo
      end
    end
  end
  
  # 
  # Processes +fields+ with <tt>@converters</tt>, or <tt>@header_converters</tt>
  # if this is a header_row?(), returning the converted field set.  Any
  # converter that changes the field into something other than a String halts
  # the pipeline of conversion for that field.  This is primarily an efficiency
  # shortcut.
  # 
  def convert_fields( fields )
    converters = if header_row?  # see if we are converting headers or fields
      @header_converters
    else
      @converters
    end
    
    fields.enum_for(:each_with_index).map do |field, index|  # map_with_index
      converters.each do |converter|
        field = if converter.arity == 1  # straight field converter
          converter[field]
        else                             # FieldInfo converter
          converter[field, FieldInfo.new(index, @io.lineno)]
        end
        break unless field.is_a? String  # short-curcuit pipeline for speed
      end
      field  # return final state of each field, converted or original
    end
  end
  
  # 
  # This methods is used to turn a finished +row+ into a FasterCSV::Row.  Header
  # rows are also dealt with here, either by returning a FasterCSV::Row with
  # identical headers and fields (save that the fields do not go through the
  # converters) or by reading past them to return a field row. Headers are also
  # saved in <tt>@headers</tt> for use in future rows.
  # 
  def parse_headers( row )
    if @headers.nil?  # header row
      @headers = convert_fields(row)  # save
      if @return_headers  # return the headers
        FasterCSV::Row.new(@headers, row, true)
      else                # skip to next field row
        shift
      end
    else              # field row
      FasterCSV::Row.new(@headers, row)
    end
  end
end

class Array
  # Equivalent to <tt>FasterCSV::generate_line(self, options)</tt>.
  def to_csv( options = Hash.new )
    FasterCSV.generate_line(self, options)
  end
end

class String
  # Equivalent to <tt>FasterCSV::parse_line(self, options)</tt>.
  def parse_csv( options = Hash.new )
    FasterCSV.parse_line(self, options)
  end
end
