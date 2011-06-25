require 'tam/record'

require 'thread' # Mutex

module TAM
  module Record
    # A Log will write to a unique ".log" file under #dir for
    # #interval seconds.  After the interval the log file has "expired"
    # The file name contains the UNIX epoch of when it will not
    # be logged into any more.
    # A Log::Importer will search for log files that have "expired".
    # The import will process each expired log file and will subsequently
    # delete them.
    class Log
      INTERVAL = 60
      DIR= "/var/log/tam".freeze

      attr_accessor :interval, :dir, :verbose
      def initialize opts = nil
        @paused = 0
        @paused_mutex = Mutex.new
        @queue = [ ]
        @queue_mutex = Mutex.new
        @stream_mutex = Mutex.new
        @write_mutex = Mutex.new
        @interval = INTERVAL
        @dir = DIR
        @verbose = 1
        opts and opts.each do | k, v |
          send(:"#{k}=", v)
        end
      end

      # Returns the current Log instance for this Thread.
      # Thread-safe and Fork-safe.
      def self.current
        if @@current_pid != $$
          @@current_pid = $$
          Thread.current[:'TAM::Record::Log.current'] = nil
        end
        Thread.current[:'TAM::Record::Log.current'] ||= self.new
      end
      @@current_pid = nil

      # Returns the underlying IO object for this Log.
      def stream
        now = ::Time.now.to_i
        @stream_mutex.synchronize do
          if @expires && now >= @expires
            @stream.close if @stream
            @stream = nil
          end
          unless @stream
            @expires = now + @interval
            @file = "#{@dir}/#{Record.make_uuid}-#{$$}-#{@expires}.log"
            @stream = File.open(@file, "w+")
            $stderr.puts "tam: #{$0} #{$$} opened #{@file.inspect}" if @verbose >= 1
          end
        end
        @stream
      end

      def to_s
        super.sub('>', " #{@file}>")
      end

      def paused?
        @paused > 0
      end

      def pause!
        @paused_mutex.synchronize do
          @paused += 1
        end
        self
      end

      def resume! force = false
        paused = @paused_mutex.synchronize do
          if force
            @paused = 0
          else
            @paused -= 1 if @paused > 0
          end
          @paused
        end
        if paused <= 0
          flush!
        end
        self
      end

      def write! rec
        str = rec.to_json
        $stderr.puts "#{$$} #{str}" if @verbose >= 2
        str = "db.tam.save(#{str});\n".freeze
        if @paused > 0
          @queue_mutex.synchronize do
            @queue << str
          end
        else
          @write_mutex.synchronize do
            _write! str
          end
        end
        self
      end

      def flush!
        queue = nil
        @queue_mutex.synchronize do
          queue = @queue.empty? ? EMPTY_Array : @queue.dup
          @queue.clear
        end
        unless queue.empty?
          @write_mutex.synchronize do
            begin
              until queue.empty?
                str = queue.first
                _write! str
                queue.shift
              end
            rescue ::Exception => exc
              # If _write failed above,
              # put remaining items back on the queue.
              @queue_mutex.synchronize do
                @queue[0, 0] = queue
              end
              raise
            end
          end
        end
        self
      end

      def flush_at_exit!
        unless @flush_at_exit
          at_exit do
            resume! true
          end
          @flush_at_exit = true
        end
        self
      end

      def _write! str
        s = stream
        s.write str
        s.flush
        self
      end

      class Importer
        attr_accessor :interval, :dir, :verbose

        def initialize
          @interval = INTERVAL
          @dir = DIR
          @verbose = 0
        end

        def _log msg = nil
          msg ||= yield if block_given?
          case msg
          when ::Exception
            Record::Error.new(msg, :in_class => self.class.name)
          else
            Record::Generic.new(msg, :in_class => self.class.name)
          end.log!
          self
        end

        def run!
          TAM::Record::Process.wrap do
            _run!
          end
        end

        def _run!
          @running = true
          # Start with any abandoned files.
          @jsfiles ||= Dir["#{@dir}/*.js"] 
          while @running
            poll!
            sleep @interval
          end
          self
        end
        
        def poll!
          @err = nil
          now = ::Time.now
          now_i = now.to_i
          @jsfiles ||= [ ]
          begin
            scan = "#{@dir}/*.log" 
            _log { "scanning #{scan}" } if @verbose >= 3
            Dir[scan].each do | logfile |
              # $stderr.puts "logfile = #{logfile.inspect}"
              if File.basename(logfile) =~ %r{-(\d+)\.log\Z}
                expires = $1.to_i
                if now_i > expires + 1
                  File.open(logfile) do | fh |
                    jsfile = "#{logfile}.js"
                    File.rename(logfile, jsfile)
                    @jsfiles << jsfile
                    _log { "prepared #{jsfile.inspect} #{File.size(jsfile)} bytes" } if @verbose >= 4
                  end
                end
              end
            end
          rescue ::Exception => @err
            _log(@err)
          end
          
          yield self if block_given?
          
          unless @jsfiles.empty?
            cmd = "mongo #{@jsfiles * " "}"
            begin
              system(cmd) or raise "#{cmd} failed"
              _log { "processed #{@jsfiles.inspect}" } if @verbose >= 4
              @jsfiles.each do | jsfile |
                File.unlink(jsfile)
              end
              @jsfiles = nil
            rescue ::Exception => @err
              $stderr.puts "ERROR: #{@err.inspect}\n  #{@err.backtrace * "\n  "}"
              _log(@err)
            end
          end

          self
        end
      end # class
    end # class
  end # class
end # module


