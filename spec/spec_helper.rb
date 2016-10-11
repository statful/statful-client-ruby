require 'bundler/setup'

require 'simplecov'
SimpleCov.start

require 'minitest/autorun'
require 'minitest/reporters'

module Minitest
  module Reporters
    class AwesomeReporter < DefaultReporter
      GREEN = '1;32'
      RED = '1;31'

      def color_up(string, color)
        color? ? "\e\[#{ color }m#{ string }#{ ANSI::Code::ENDCODE }" : string
      end

      def red(string)
        color_up(string, RED)
      end

      def green(string)
        color_up(string, GREEN)
      end
    end
  end
end

Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new({:color => true, :slow_count => 5 }))

require 'statful-client'

# Shamelessly stolen from the statsd-ruby client
class FakeUDPSocket
  attr_accessor :buffer

  def initialize
    @buffer = Queue.new
  end

  def send(message)
    @buffer.push(message)
  end

  def recv
    @buffer.shift
  end

  def clear
    @buffer = Queue.new
  end

  def to_s
    inspect
  end

  def inspect
    "<#{self.class.name}: #{@buffer.inspect}>"
  end
end
