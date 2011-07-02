require 'tam'

require 'rubygems'
gem 'json'
require 'json'

require 'socket' # .gethostname
require 'time' # .parse, #iso8601
require 'thread' # Mutex

module TAM
  module Record
    # Returns a process-unique UUID; it is unique even if this process forks.
    # Thread-safe.
    def self.puuid
      @@puuid_mutex.synchronize do
        if @@puuid_pid != $$
          @@puuid_pid = $$
          @@puuid = nil
        end
        @@puuid ||= 
          File.read(PROC_SYS_FILE).chomp.freeze
      end
    end
    PROC_SYS_FILE = "/proc/sys/kernel/random/uuid".freeze
    @@puuid_mutex = Mutex.new
    @@puuid_pid = nil

    # Returns a new UUID based on #puuid.
    # Thread-safe.
    def self.make_uuid
      @@uuid_mutex.synchronize do
        "#{puuid}-#{@@uuid_counter += 1}"
      end
    end
    @@uuid_mutex = Mutex.new
    @@uuid_counter ||= 0

    # Returns the current hostname.
    def self.hostname
      @@hostname ||= Socket.gethostname.dup.freeze
    end
    @@hostname = nil

    # Base class for all records.
    class Base
      attr_accessor :_id, :t, :kind
      attr_reader :data

      def initialize kind = nil, data = nil
        @kind = kind
        @data = data || EMPTY_Hash
        _id
        t
        instance_eval if block_given?
      end

      def [] k
        @data[k]
      end

      def []= k, v
        @data = @data.dup if @data.frozen?
        @data[k] = v
      end

      def _id
        @_id ||= @data[:_id] || Record.make_uuid.freeze
      end
      alias :id :_id
      
      def t
        @t ||= 
          begin
            # $stderr.puts "t : @data = #{@data.inspect}"
            x = @data[:t]
            x = nil if x == NOW
            # Attempt to parse Time from String.
            # $stderr.puts "t : x = #{x.inspect}"
            if ::String === x
              (x = ::Time.parse(x).utc) rescue nil
            end
            x ||= ::Time.now.utc
            # $stderr.puts "t : @t = #{x.inspect}"
            x
          end
        @t
      end
      NOW = 'now'.freeze

      def puuid
        @puuid ||= @data[:puuid] || Record.puuid
      end

      def completes! rec
        if rec && ! @completes
          @dt = @t - rec.t
          @completes = rec._id
        end
        self
      end

      def parent! rec
        if rec
          (@parents ||= [ ]) << rec._id
        end
        self
      end

      def to_hash
        h = @data ||= { }
        h = h.dup if h.frozen?
        h[:_id] ||= _id
        h[:t] = TimeWrapper.new(t)
        h[:puuid] ||= puuid
        h[:kind] ||= @kind if @kind
        h[:dt] ||= @dt if @dt
        h[:completes] ||= @completes if @completes
        h[:parents] ||= @parents if @parents && ! @parents.empty?
        if String === (parents = h[:parents])
          h[:parents] = parents.split(/\s*,\s*|\s+/)
        end
        h
      end

      def _to_json
        debugger rescue nil
        @_to_json ||=
          JSON.generate(to_hash).
          freeze
      end

      def log!
        unless @logged
          Log.current.write! self
          @logged = true
        end
        self
      end

    end # class

    # Standin for ::Time or ::String to force ISODate("...") format from #to_json
    class TimeWrapper
      def initialize t
        @t = t
      end

      def to_json options = nil
        # $stderr.puts "@t = #{@t.inspect}"
        case @t
        when ::Time
          str = @t.iso8601(3)
        when ::String
          str = @t
        else
          raise TypeError, "#{@t.class}"
        end
        %Q{ISODate("#{str}")}
      end
      def to_ruby
        @t
      end
    end # class

    # Process-oriented records: process start/stop.
    class Process < Base
      def initialize k, data = nil
        super(:"process.#{k}", data)
      end

      def self.current data = nil
        @@current_mutex.synchronize do
        if @@current_pid != $$
          @@current_pid = $$
          @@parent = @@current
          @@current = nil
        end
        unless @@current
          data ||= { }
          data[:_id] = data[:puuid] = Record.puuid
          @@current = self.new(:start, data).parent!(@@parent).log!
          at_exit do
            self.new(:end).completes!(@@current).log!
          end
        end
        @@current
        end
      end
      @@current_pid = @@current = nil
      @@current_mutex = Mutex.new
      @@parent = nil

      def self.wrap data = nil
        raise ArgumentError, "expected block" unless block_given?
        return yield if @wrapped > 0
        @wrapped += 1
        proc_begin = current(data)
        yield
      rescue ::Exception => exc
        $stderr.puts "#{self}: ERROR #{exc.inspect}\n  #{exc.backtrace * "\n  "}"
        TAM::Record::Error.new(exc).parent!(proc_begin).log!
        raise
      ensure
        @wrapped -= 1
        Log.current.flush! if @wrapped == 0
      end
      @wrapped ||= 0

      def host
        @host ||= @data[:host] || Record.hostname
      end
      
      def progname
        @progname ||= @data[:progname] || $0.dup.freeze
      end

      def to_hash
        h = super
        if @kind == :'process.start'
          h[:progname] ||= progname
          h[:host] ||= host 
          h[:pid] ||= $$ 
        end
        h
      end
    end # class

    # Error-oriented records: Exceptions, etc.
    class Error < Base
      def initialize e, data = nil
        super(:error, data)
        @e = e
      end
      def msg
        @msg ||= @e.message.dup.freeze
      end
      def e_class
        @e_class ||= @e.class.name.freeze
      end
      def e_bt
        @e_bt ||= @e.backtrace.dup.freeze
      end
      def to_hash
        h = super
        case @e 
        when String
          h[:msg] ||= @e
        else
          h[:msg] ||= msg
          h[:e_class] ||= e_class
          h[:e_bt] ||= e_bt
        end
        h
      end
    end # class

    # Generic record: status
    class Generic < Base
      def initialize msg = nil, data = nil
        super(:generic, data)
        @msg = msg && msg.to_s
      end
      def to_hash
        h = super
        h[:msg] ||= @msg if @msg
        h
      end
    end

  end
end

require 'tam/record/log'


