require 'log4r'

require 'tam/log4r/tam_formatter'
require 'tam/log4r/tam_outputter'

module Log4r
  TamFormatter = ::TAM::Log4r::TamFormatter
  TamOutputter = ::TAM::Log4r::TamOutputter
end
