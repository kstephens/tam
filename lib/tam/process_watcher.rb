require 'tam'

module TAM
  class ProcessWatcher
    def initialize
      @ps = [ ]
      @p_by_pid = { }
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
      recs = [ ]

      ps = get_current_processes
      p_by_pid = { }

      ps.each do | np |
        p_by_pid[np[:pid]] = np

        # Previous process exists?
        if cp = @p_by_pid[np[:pid]]
          #
        else
          data = np[:data] ||= 
            begin
              data = np.dup
              data[:progname] = data.delete(:cmd)
              data.delete(:ppid)
              data[:puuid] = TAM::Record.make_uuid
              data
            end
          recs << np[:_s_rec] = TAM::Record::Process.new(:start, data)
        end
      end

      @ps.each do | cp |
        if np = p_by_pid[cp[:pid]]
        else
          # Previous process does not exist anymore.
          data = cp[:data]
          recs << cp[:_e_rec] = TAM::Record::Process.new(:end, data).completes!(cp[:_s_rec])
        end
      end

      # Link parent and child
      (@ps + ps).each do | np |
        parents = [ p_by_pid[np[:ppid]] || @p_by_pid[np[:ppid]] ]
        parents.compact!
        parents.map! { | p | np[:_s_rec].parent!(p[:_s_rec]) }
      end

      @ps = ps
      @p_by_pid = p_by_pid

      recs.each do | rec |
        rec.log!
      end

      recs
    end

  end
end

require 'pp'
watcher = TAM::ProcessWatcher.new
pp watcher.get_current_processes
pp watcher.poll!.map{|r| r.to_json}

