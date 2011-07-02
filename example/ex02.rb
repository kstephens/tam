require 'rubygems'
gem 'log4r'
require 'log4r'
require 'tam'
require 'tam/log4r'
require 'pp'
require 'ruby-debug'


TAM::Record::Log.current.verbose = 9

TAM::Record::Process.wrap do
  logger = Log4r::Logger.new("tam_logger")
  logger.add(Log4r::IOOutputter.new("stderr_outputter", STDERR))
  o = Log4r::TamOutputter.new("tam_outputter")
  logger.add(o)
  logger.info do
    { :msg => "this use logged in", :user_id => 1234 }
  end
  logger.error do
    { :msg => "error: user failed", :user_id => 1234 }
  end
end

