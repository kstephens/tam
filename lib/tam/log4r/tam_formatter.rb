module TAM
  module Log4r
    class TamFormatter < ::Log4r::Formatter
      # Additional data to add to the TAM::Record before logging it.
      attr_accessor :hash_data

      def initialize *args
        super
        @hash_data = { }
      end

      def format event
        event
      end
    end
  end
end
