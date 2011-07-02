require 'tam'

require 'tam/record'
require 'tam/record/log'

module TAM
  class Main
    attr_accessor :args, :verb, :debug, :subject

    def run!
      self.args = ARGV.dup

      if debug
        $stderr.puts "#{ARGV.inspect}"
        # debugger
      end
      
      self.verb = args.shift
      self.subject = args.shift
      
      case verb
      when 'help'
        usage

      when 'log'
        msg = args.shift
        data = parse_opts! args
        
        cls = case subject
              when 'generic'
                TAM::Record::Generic
              when 'error'
                TAM::Record::Error
              else
                raise "tam: #{verb} : unknown subject #{subject.inspect}"
              end
        cls.new(msg, data).log!
        
      when 'run'
        TAM::Record::Process.wrap(:args => args, :verb => verb, :subject => subject) do
          case subject
          when 'importer'
            TAM::Record::Log::Importer.new._run!
          when 'process_watcher'
            require 'tam/process_watcher'
            opts = parse_opts!
            TAM::ProcessWatcher.new(opts)._run!
          else
            raise "tam: #{verb} : unknown subject #{subject.inspect}"
          end
        end
      else
        raise "tam: unknown verb #{verb.inspect}"
      end
      
      self
    end
    
    def usage
      $stderr.puts <<"END"
tam - generic event loging

tam log TYPE

tam log generic MSG [ --ATTR VALUE ] ...

tam log error MSG [ --ATTR VALUE ] ...

tam run THING

tam run importer [ --dir DIR ]

tam run process_watcher [ --state_file filename ]

END
    end

    def parse_opts! args = self.args
      data = { }
      until args.empty?
        k = args.shift.sub(/^--?/, '')
        k = k.to_sym
        v = args.shift
        # If it smells like an Integer, make it so.
        if k != :t and vi = v.to_i and vi.to_s == v
          v = vi
        end
        data[k] = v
      end
      data
    end
    
  end
end

