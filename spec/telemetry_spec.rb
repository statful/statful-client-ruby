require 'spec_helper'
require 'logger'
require 'stringio'

class TelemetronClient
  public :buffer
  public :logger
  attr_accessor :config
  attr_accessor :socket

  def socket
    Thread.current[:telemetron_socket] ||= FakeUDPSocket.new
  end
end

describe TelemetronClient do
  before do
    @log = StringIO.new
    @telemetron = TelemetronClient.new({'prefix' => 'test_prefix',
                                        'app' => 'test_app',
                                        'dryrun' => false,
                                        'logger' => Logger.new(@log),
                                        'tags' => {'tag' => 'test_tag'},
                                        'flush_size' => 1
                                       })
  end

  after do
    Thread.current[:telemetron_socket] = nil
  end

  describe '#initialize' do
    it 'should symbolize config keys' do
      @telemetron.config[:prefix].must_equal 'test_prefix'
    end

    it 'should set the default config' do
      @telemetron.config[:host].must_equal '127.0.0.1'
      @telemetron.config[:port].must_equal 2013
      @telemetron.config[:prefix].must_equal 'test_prefix'
      @telemetron.config[:app].must_equal 'test_app'
      @telemetron.config[:dryrun].must_equal false
      @telemetron.config[:tags].must_equal Hash[{:tag => 'test_tag'}]
      @telemetron.config[:sample_rate].must_equal 100
      @telemetron.config[:flush_size].must_equal 1
    end

    it 'should create an empty buffer' do
      @telemetron.buffer.must_equal []
    end

    it 'should raise ArgumentError if prefix is undefined' do
      begin
        TelemetronClient.new
      rescue => ex
        ex.must_be_kind_of ArgumentError
      end
    end

    it 'should raise ArgumentError if sample_rate is not within range (1-100)' do
      begin
        TelemetronClient.new({:sample_rate => 101})
      rescue => ex
        ex.must_be_kind_of ArgumentError
      end
    end
  end

  describe '#timer' do
    it 'should format the message according to the telemetron spec' do
      @telemetron.timer('test_metric', 500)
      @telemetron.socket.recv =~ /^test_prefix.application.timer.test_metric,unit=ms,app=test_app,tag=test_tag 500 \d+ avg,p90,count,count_ps,10$/
    end

    describe 'with a custom tag' do
      it 'should format the message according to the telemetron spec' do
        @telemetron.timer('test_metric', 500, {:tags => {:tag => 'test_custom_tag'}})
        @telemetron.socket.recv =~ /^test_prefix.application.timer.test_metric,app=test_app,tag=test_custom_tag,unit=ms 500 \d+ avg,p90,count,count_ps,10$/
      end
    end

    describe 'with a custom aggregation' do
      it 'should format the message according to the telemetron spec' do
        @telemetron.timer('test_metric', 500, {:agg => ['avg'], :agg_freq => 30})
        @telemetron.socket.recv =~ /^test_prefix.application.timer.test_metric,unit=ms,app=test_app,tag=test_tag 500 \d+ avg,30$/
      end
    end

    describe 'with a custom namespace' do
      it 'should format the message according to the telemetron spec' do
        @telemetron.timer('test_metric', 500, {:namespace => 'test_namespace'})
        @telemetron.socket.recv =~ /^test_prefix.test_namespace.timer.test_metric,unit=ms,app=test_app,tag=test_tag 500 \d+ avg,p90,count,count_ps,10$/
      end
    end

    describe 'with a 0 sample rate' do
      before do
        @telemetron.config[:sample_rate] = 0
      end

      after do
        @telemetron.config[:sample_rate] = nil
      end

      it 'should not push any metric into the buffer' do
        buffer_prev_size = @telemetron.buffer.size
        @telemetron.timer('test_metric', 500)
        @telemetron.buffer.size.must_equal buffer_prev_size
      end
    end

    describe 'with dryrun enabled' do
      before do
        @telemetron.config[:dryrun] = true
      end

      after do
        @telemetron.config[:dryrun] = false
      end

      it 'should not flush any metric but clear the buffer' do
        @telemetron.buffer.clear
        @telemetron.timer('test_dryrun', 500)
        @log.string =~ /Flushing metrics: test_prefix.application.timer.test_dryrun,unit=ms,app=test_app,tag=test_tag 500 \d+ avg,p90,count,count_ps,10/
        @telemetron.socket.buffer.must_equal []
        @telemetron.buffer.size.must_equal 0
      end
    end

    describe 'without app configured' do
      before do
        @telemetron.config.delete(:app)
      end

      after do
        @telemetron.config[:app] = 'application'
      end

      it 'should format the message according to the telemetron spec' do
        @telemetron.timer('test_metric', 500)
        @telemetron.socket.recv =~ /^test_prefix.timer.test_metric,unit=ms,app=test_app,tag=test_tag 500 \d+ avg,p90,count,count_ps,10$/
      end
    end
  end

  describe '#counter' do
    it 'should format the message according to the telemetron spec' do
      @telemetron.counter('test_metric', 10)
      @telemetron.socket.recv =~ /^test_prefix.application.counter.test_metric,app=test_app,tag=test_tag 10 \d+ sum,count,count_ps,10$/
      @telemetron.counter('test_metric', -10)
      @telemetron.socket.recv =~ /^test_prefix.application.counter.test_metric,app=test_app,tag=test_tag -10 \d+ sum,count,count_ps,10$/
    end

    describe 'with a float value' do
      it 'should cast the value to int' do
        @telemetron.counter('test_metric', 10.123)
        @telemetron.socket.recv =~ /^test_prefix.application.counter.test_metric,app=test_app,tag=test_tag 10 \d+ sum,count,count_ps,10$/
      end
    end
  end

  describe '#gauge' do
    it 'should format the message according to the telemetron spec' do
      @telemetron.gauge('test_metric', 256)
      @telemetron.socket.recv =~ /^test_prefix.application.gauge.test_metric,app=test_app,tag=test_tag 256 \d+ last,10$/
      @telemetron.gauge('test_metric', -1234.56)
      @telemetron.socket.recv =~ /^test_prefix.application.gauge.test_metric,app=test_app,tag=test_tag -1234.56 \d+ last,10$/
    end
  end

  describe '#flush_metrics' do
    it 'should flush all metrics in the buffer' do
      @telemetron.timer('test', 1)
      @telemetron.flush_metrics
      @telemetron.buffer.size.must_equal 0
    end
  end

  describe 'supporting logger' do
    it 'should write to the log in debug' do
      @telemetron.logger.level = Logger::DEBUG
      @telemetron.timer('test_log', 500)
      @log.string =~ /^test_prefix.application.timer.test_log,unit=ms,app=test_app,tag=test_tag 500 \d+ avg,p90,count,count_ps,10$/
    end

    it 'should not write to the log unless debug' do
      @telemetron.logger.level = Logger::INFO
      @telemetron.timer('test_log', 500)
      @log.string.must_be_empty
    end
  end

  describe 'handling socket errors' do
    before do
      @telemetron.socket.instance_eval do
        def send(*) raise SocketError end
      end
    end

    after do
      @telemetron.socket = Thread.current[:telemetron_socket] ||= FakeUDPSocket.new
    end

    it 'should ignore socket errors' do
      @telemetron.timer('test_sock', 1).must_equal false
    end

    it 'should log socket errors' do
      @telemetron.timer('test_sock', 1)
      @log.string.must_match 'Telemetron: SocketError on 127.0.0.1:2013'
    end
  end

  describe 'thread safety' do
    before do
      @telemetron.timer('test', 1)
    end

    after do
      @telemetron.flush_metrics
    end

    it 'should use a thread local socket' do
      Thread.current[:telemetron_socket].must_equal @telemetron.socket
      @telemetron.send(:socket).must_equal @telemetron.socket
    end

    it 'should create a new socket when used in a new thread' do
      sock = @telemetron.send(:socket)
      Thread.new { Thread.current[:telemetron_socket] }.value.wont_equal sock
    end
  end
end
