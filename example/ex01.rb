$:.unshift(File.expand_path('../../lib', __FILE__))

require 'tam/record'

TAM::Record::Log.current.pause!.flush_at_exit!

TAM::Record::Process.wrap do
  sleep 1
  raise TypeError, "I WANT A COOKIE!"
end

