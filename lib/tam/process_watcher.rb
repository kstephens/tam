require 'tam'

module TAM
  class ProcessWatcher
    attr_accessor :state_file, :interval, :verbose

    def initialize opts = nil
      @interval = 10
      @verbose = 0
      @state_file = "/var/run/tam/process_watcher.state"
      @ps = [ ]
      @p_by_pid = { }
      opts && opts.each do | k, v |
        send(:"#{k}=", v)
      end
      require 'pp'; pp self
    end

    def run!
      _run!
    end

    def _run!
      state! :restore
      @running = true
      while @running
        poll!
        if true || @verbose >= 1 and @ps_started > 0 || @ps_exited > 0
          $stderr.puts "#{self.class} #{$$} #{@now.iso8601(3)} : #{@ps.size} processes (#{@ps_started} started) (#{@ps_exited} exited)"
        end
        sleep @interval
      end
      state! :save
      self
    end

    def get_current_processes
      lines = `ps -eF`.split("\n")
      header = lines.shift
      header = header.split(/\s+/)
      col_to_key = { }; col = -1
      header.each do | h |
        h.downcase!
        col_to_key[col += 1] = h.to_sym
      end
      lines.map do | line |
        process = { }
        col = -1
        line.split(/\s+/).each do | v |
          if vi = v.to_i and vi.to_s == v
            v = vi
          end
          process[col_to_key[col += 1]] = v
        end
        process
      end
    end

    def poll!
      now = Time.new.utc

      recs = [ ]

      ps = get_current_processes
      # Filter out:
      # * init
      # * this process
      # * any children of this process.
      ps.delete_if { | np | np[:pid] == 1 or np[:pid] == $$ or np[:ppid] == $$ }
      p_by_pid = { }

      @ps_started = @ps_exited = 0

      ps.each do | np |
        p_by_pid[np[:pid]] = np

        # Previous process exists?
        if cp = @p_by_pid[np[:pid]] and cp[:ppid] == np[:ppid]
          #
        else
          # New process.
          next if np[:pid] == 1 # Ignore init
          data = np[:data] ||= {
            :progname => np[:cmd].split(/\s+/, 2).first,
            :puuid => TAM::Record.make_uuid,
            :uid => np[:uid],
            :pid => np[:pid],
          }
          data[:_id] = data[:puuid]
          rec = 
            TAM::Record::Process.
            new(:start, data)
          np[:s_rec] = rec
          recs << rec
          @ps_started += 1
        end
      end

      @ps.each do | cp |
        if np = p_by_pid[cp[:pid]] and np[:ppid] == cp[:ppid]
        else
          # Previous process does not exist anymore.
          data = cp[:data]
          rec = 
            TAM::Record::Process.
            new(:end, :puuid => data ? data[:puuid] : 'UNKNOWN').
            completes!(cp[:s_rec])
          recs << rec
          @ps_exited += 1
        end
      end

      # Link parent and child
      (@ps + ps).each do | np |
        rec = np[:s_rec]
        next unless rec
        parents = [ p_by_pid[np[:ppid]] || @p_by_pid[np[:ppid]] ]
        parents.compact!
        parents.each { | pp | rec.parent!(pp[:s_rec]) }
      end

      @now = now
      @ps = ps
      @p_by_pid = p_by_pid

      recs.each do | rec |
        rec.log!
      end
     
      self
    ensure 
      state! :save
    end

    def state! action
      case action
      when :save
        state = self
        File.open(@state_file, "w+") do | io |
          io.write(Marshal.dump(self))
        end
        File.chmod(0666, @state_file) rescue nil
      when :restore
        state = nil
        File.open(@state_file) do | io |
          state = Marshal.load(io)
        end rescue nil
        if state
          state.instance_variables.each do | ivar |
            instance_variable_set(ivar, state.instance_variable_get(ivar))
          end
          $stderr.puts "#{self.class} #{$$} : restored from #{@state_file} : #{@ps.size} processes at #{@now.iso8601(3)}"
        end
      end
      self
    end

  end
end


