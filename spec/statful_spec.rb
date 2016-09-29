require 'spec_helper'
require 'logger'
require 'stringio'

class StatfulClient
  public :buffer
  public :logger
  attr_accessor :config
  attr_accessor :socket
  attr_accessor :udp_socket

  def udp_socket
    Thread.current[:statful_socket] ||= FakeUDPSocket.new
  end
end

describe StatfulClient do
  before do
    @log = StringIO.new
    @statful = StatfulClient.new({'transport' => 'udp',
                                  'token' => 'test',
                                  'app' => 'test_app',
                                  'dryrun' => false,
                                  'logger' => Logger.new(@log),
                                  'tags' => {:tag => 'test_tag'},
                                  'flush_size' => 1
                                 })
  end

  after do
    Thread.current[:statful_socket] = nil
  end

  describe '#initialize' do
    it 'should symbolize config keys' do
      @statful.config[:transport].must_equal 'udp'
    end

    it 'should set the default config' do
      @statful.config[:host].must_equal 'api.statful.com'
      @statful.config[:port].must_equal 443
      @statful.config[:transport].must_equal 'udp'
      @statful.config[:app].must_equal 'test_app'
      @statful.config[:dryrun].must_equal false
      @statful.config[:tags].must_equal Hash[{:tag => 'test_tag'}]
      @statful.config[:sample_rate].must_equal 100
      @statful.config[:namespace].must_equal 'application'
      @statful.config[:flush_size].must_equal 1
    end

    it 'should create an empty buffer' do
      @statful.buffer.must_equal []
    end

    it 'should raise ArgumentError if transport is missing' do
      begin
        StatfulClient.new
      rescue => ex
        ex.must_be_kind_of ArgumentError
      end
    end

    it 'should raise ArgumentError if transport is invalid' do
      begin
        StatfulClient.new({:transport => 'invalid'})
      rescue => ex
        ex.must_be_kind_of ArgumentError
      end
    end

    it 'should raise ArgumentError if token is missing' do
      begin
        StatfulClient.new({:transport => 'http'})
      rescue => ex
        ex.must_be_kind_of ArgumentError
      end
    end

    it 'should raise ArgumentError if sample_rate is not within range (1-100)' do
      begin
        StatfulClient.new({:sample_rate => 101})
      rescue => ex
        ex.must_be_kind_of ArgumentError
      end
    end
  end

  describe '#timer' do
    it 'should format the message according to the statful spec' do
      @statful.timer('test_metric', 500)
      @statful.udp_socket.recv.must_match(/^application.timer.test_metric,tag=test_tag,unit=ms,app=test_app 500 \d+ avg,p90,count,10 100$/)
    end

    describe 'with a custom tag' do
      it 'should format the message according to the statful spec' do
        @statful.timer('test_metric', 500, {:tags => {:tag => 'test_custom_tag'}})
        @statful.udp_socket.recv.must_match(/^application.timer.test_metric,tag=test_custom_tag,unit=ms,app=test_app 500 \d+ avg,p90,count,10 100$/)
      end
    end

    describe 'with a custom aggregation' do
      it 'should format the message according to the statful spec' do
        @statful.timer('test_metric', 500, {:agg => ['max'], :agg_freq => 30})
        @statful.udp_socket.recv.must_match(/^application.timer.test_metric,tag=test_tag,unit=ms,app=test_app 500 \d+ avg,p90,count,max,30 100$/)
      end
    end

    describe 'with a custom namespace' do
      it 'should format the message according to the statful spec' do
        @statful.timer('test_metric', 500, {:namespace => 'test_namespace'})
        @statful.udp_socket.recv.must_match(/^test_namespace.timer.test_metric,tag=test_tag,unit=ms,app=test_app 500 \d+ avg,p90,count,10 100$/)
      end
    end

    describe 'with a 0 sample rate' do
      before do
        @statful.config[:sample_rate] = 0
      end

      after do
        @statful.config[:sample_rate] = nil
      end

      it 'should not push any metric into the buffer' do
        buffer_prev_size = @statful.buffer.size
        @statful.timer('test_metric', 500)
        @statful.buffer.size.must_equal buffer_prev_size
      end
    end

    describe 'with dryrun enabled' do
      before do
        @statful.config[:dryrun] = true
      end

      after do
        @statful.config[:dryrun] = false
      end

      it 'should not flush any metric but clear the buffer' do
        @statful.buffer.clear
        @statful.timer('test_dryrun', 500)
        @log.string.must_match(/Flushing metrics: application.timer.test_dryrun,tag=test_tag,unit=ms,app=test_app 500 \d+ avg,p90,count,10 100/)
        @statful.udp_socket.buffer.must_equal []
        @statful.buffer.size.must_equal 0
      end
    end

    describe 'without app configured' do
      before do
        @statful.config.delete(:app)
      end

      after do
        @statful.config[:app] = 'test_app'
      end

      it 'should format the message according to the statful spec' do
        @statful.timer('test_metric', 500)
        @statful.udp_socket.recv.must_match(/^application.timer.test_metric,tag=test_tag,unit=ms 500 \d+ avg,p90,count,10 100$/)
      end
    end
  end

  describe '#counter' do
    it 'should format the message according to the statful spec' do
      @statful.counter('test_metric', 10)
      @statful.udp_socket.recv.must_match(/^application.counter.test_metric,tag=test_tag,app=test_app 10 \d+ sum,count,10 100$/)
      @statful.counter('test_metric', -10)
      @statful.udp_socket.recv.must_match(/^application.counter.test_metric,tag=test_tag,app=test_app -10 \d+ sum,count,10 100$/)
    end

    describe 'with a float value' do
      it 'should cast the value to int' do
        @statful.counter('test_metric', 10.123)
        @statful.udp_socket.recv.must_match(/^application.counter.test_metric,tag=test_tag,app=test_app 10 \d+ sum,count,10 100$/)
      end
    end
  end

  describe '#gauge' do
    it 'should format the message according to the statful spec' do
      @statful.gauge('test_metric', 256)
      @statful.udp_socket.recv.must_match(/^application.gauge.test_metric,tag=test_tag,app=test_app 256 \d+ last,10 100$/)
      @statful.gauge('test_metric', -1234.56)
      @statful.udp_socket.recv.must_match(/^application.gauge.test_metric,tag=test_tag,app=test_app -1234.56 \d+ last,10 100$/)
    end
  end

  describe '#put' do
    it 'should format the message according to the statful spec' do
      options = {:tags => {}, :agg => [], :sample_rate => 100, :namespace => 'application'}

      @statful.put('test_metric', 256, options)
      @statful.udp_socket.recv.must_match(/^application.test_metric,tag=test_tag,app=test_app 256 \d+ 100$/)
    end

    describe 'with an explicit timestamp' do
      it 'should format the message according to the statful spec' do
        options = {:tags => {}, :agg => [], :sample_rate => 100, :namespace => 'application', :timestamp => 12345}

        @statful.put('test_metric', 256, options)
        @statful.udp_socket.recv.must_match(/^application.test_metric,tag=test_tag,app=test_app 256 12345 100$/)
      end
    end

    describe 'without sample rate' do
      it 'should apply the default sample rate and format the message according to the statful spec' do
        options = {:tags => {}, :agg => [], :namespace => 'application', :timestamp => 12345}

        @statful.put('test_metric', 256, options)
        @statful.udp_socket.recv.must_match(/^application.test_metric,tag=test_tag,app=test_app 256 12345 100$/)
      end
    end
  end

  describe '#flush_metrics' do
    it 'should flush all metrics in the buffer' do
      @statful.timer('test', 1)
      @statful.flush_metrics
      @statful.buffer.size.must_equal 0
    end
  end

  describe 'supporting logger' do
    it 'should write to the log in debug' do
      @statful.logger.level = Logger::DEBUG
      @statful.timer('test_log', 500)
      @log.string.must_match(/Flushing metrics: application.timer.test_log,tag=test_tag,unit=ms,app=test_app 500 \d+ avg,p90,count,10 100/)
    end

    it 'should not write to the log unless debug' do
      @statful.logger.level = Logger::INFO
      @statful.timer('test_log', 500)
      @log.string.must_be_empty
    end
  end

  describe 'handling udp socket errors' do
    before do
      @statful.config[:transport] = 'udp'
      @statful.config[:dryrun] = false
      @statful.udp_socket.instance_eval do
        def send(*) raise SocketError end
      end
    end

    after do
      @statful.udp_socket = Thread.current[:statful_socket] ||= FakeUDPSocket.new
      @statful.config[:transport] = 'http'
      @statful.config[:dryrun] = true
    end

    it 'should ignore udp socket errors' do
      @statful.timer('test_sock', 1).must_equal false
    end

    it 'should log udp socket errors' do
      @statful.timer('test_sock', 1)
      @log.string.must_match 'Statful: SocketError on api.statful.com:443'
    end
  end

  describe 'thread safety' do
    before do
      @statful.config[:transport] = 'udp'
      @statful.config[:dryrun] = false
      @statful.timer('test', 1)
    end

    after do
      @statful.flush_metrics
      @statful.config[:transport] = 'http'
      @statful.config[:dryrun] = true
    end

    it 'should use a thread local udp socket' do
      Thread.current[:statful_socket].must_equal @statful.udp_socket
    end

    it 'should create a new local udp socket when used in a new thread' do
      Thread.new { Thread.current[:statful_socket] }.value.wont_equal @statful.udp_socket
    end
  end
end
