module TAM
  module Log4r
    class TamOutputter < ::Log4r::Outputter
      # Additional data to add to the TAM::Record before logging it.
      attr_accessor :hash_data

      def initialize *args
        super
        @formatter = TamFormatter.new
        @hash_data = { }
      end

      # TAM is already thread-safe so do not bother with #synch.
      def canonical_log logevent
        write(format(logevent))
      end

      # Creates a TAM record.
      def write data # data == logevent
        msg = nil
        h = @hash_data.dup
        h.update(@formatter.hash_data) if @formatter.respond_to?(:hash_data)
        h[:log4r_level] = data.level
        case msg = data.data
        when ::String
        when ::Hash
          h.update(msg)
          msg = hash[:msg] || UNKNOWN_MSG
        when ::Exception
          msg = data.message
        else
          msg = msg.inspect
        end
        TAM::Record::Generic.new(msg, h).log!
      end

      UNKNOWN_MSG = 'UNKNOWN'.freeze
    end
  end
end
