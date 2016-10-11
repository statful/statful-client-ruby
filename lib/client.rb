require 'socket'
require 'delegate'
require 'net/http'
require 'concurrent'

# Statful Client Instance
#
# @attr_reader config [Hash] Current client config
class StatfulClient
  attr_reader :config

  def new
    self
  end

  # Initialize the client
  #
  # @param [Hash] config Client bootstrap configuration
  # @option config [String] :host Destination host *required*
  # @option config [String] :port Destination port *required*
  # @option config [String] :transport Transport protocol, one of (udp or http) *required*
  # @option config [Integer] :timeout Timeout for http transport
  # @option config [String] :token Authentication account token for http transport
  # @option config [String] :app Global metric app tag
  # @option config [TrueClass/FalseClass] :dryrun Enable dry-run mode
  # @option config [Object] :logger Logger instance that supports debug (if dryrun is enabled) and error methods
  # @option config [Hash] :tags Global list of metric tags
  # @option config [Integer] :sample_rate Global sample rate (as a percentage), between: (1-100)
  # @option config [String] :namespace Global default namespace
  # @option config [Integer] :flush_size Buffer flush upper size limit
  # @option config [Integer] :thread_pool_size Thread pool upper size limit
  # @return [Object] The Statful client
  def initialize(config = {})
    user_config = MyHash[config].symbolize_keys

    if !user_config.has_key?(:transport) || !%w(udp http).include?(user_config[:transport])
      raise ArgumentError.new('Transport is missing or invalid')
    end

    if user_config[:transport] == 'http'
      raise ArgumentError.new('Token is missing') if user_config[:token].nil?
    end

    if user_config.has_key?(:sample_rate) && !user_config[:sample_rate].between?(1, 100)
      raise ArgumentError.new('Sample rate is not within range (1-100)')
    end

    default_config = {
      :host => 'api.statful.com',
      :port => 443,
      :transport => 'http',
      :tags => {},
      :sample_rate => 100,
      :namespace => 'application',
      :flush_size => 5,
      :thread_pool_size => 5
    }

    @config = default_config.merge(user_config)
    @logger = @config[:logger]

    @buffer = MyQueue.new
    @pool = Concurrent::FixedThreadPool.new(@config[:thread_pool_size])

    @http = Net::HTTP.new(@config[:host], @config[:port])
    @http.use_ssl = true # must enforce use of ssl, otherwise it will raise EOFError: end of file reached

    self
  end

  # Sends a timer
  #
  # @param name [String] Name of the timer
  # @param value [Numeric] Value of the metric
  # @param [Hash] options The options to apply to the metric
  # @option options [Hash] :tags Tags to associate to the metric
  # @option options [Array<String>] :agg List of aggregations to be applied by Statful
  # @option options [Integer] :agg_freq Aggregation frequency in seconds
  # @option options [String] :namespace Namespace of the metric
  def timer(name, value, options = {})
    tags = @config[:tags].merge({:unit => 'ms'})
    tags = tags.merge(options[:tags]) unless options[:tags].nil?

    aggregations = %w(avg p90 count)
    aggregations.concat(options[:agg]) unless options[:agg].nil?

    opts = {
      :agg_freq => 10,
      :namespace => 'application'
    }.merge(MyHash[options].symbolize_keys)

    opts[:tags] = tags
    opts[:agg] = aggregations

    _put("timer.#{name}", opts[:tags], value, opts[:agg], opts[:agg_freq], @config[:sample_rate], opts[:namespace])
  end

  # Sends a counter
  #
  # @param name [String] Name of the counter
  # @param value [Numeric] Increment/Decrement value, this will be truncated with `to_int`
  # @param [Hash] options The options to apply to the metric
  # @option options [Hash] :tags Tags to associate to the metric
  # @option options [Array<String>] :agg List of aggregations to be applied by the Statful
  # @option options [Integer] :agg_freq Aggregation frequency in seconds
  # @option options [String] :namespace Namespace of the metric
  def counter(name, value, options = {})
    tags = @config[:tags]
    tags = tags.merge(options[:tags]) unless options[:tags].nil?

    aggregations = %w(sum count)
    aggregations.concat(options[:agg]) unless options[:agg].nil?

    opts = {
      :agg_freq => 10,
      :namespace => 'application'
    }.merge(MyHash[options].symbolize_keys)

    opts[:tags] = tags
    opts[:agg] = aggregations

    _put("counter.#{name}", opts[:tags], value.to_i, opts[:agg], opts[:agg_freq], @config[:sample_rate], opts[:namespace])
  end

  # Sends a gauge
  #
  # @param name [String] Name of the gauge
  # @param value [Numeric] Value of the metric
  # @param [Hash] options The options to apply to the metric
  # @option options [Hash] :tags Tags to associate to the metric
  # @option options [Array<String>] :agg List of aggregations to be applied by Statful
  # @option options [Integer] :agg_freq Aggregation frequency in seconds
  # @option options [String] :namespace Namespace of the metric
  def gauge(name, value, options = {})
    tags = @config[:tags]
    tags = tags.merge(options[:tags]) unless options[:tags].nil?

    aggregations = %w(last)
    aggregations.concat(options[:agg]) unless options[:agg].nil?

    opts = {
      :agg_freq => 10,
      :namespace => 'application'
    }.merge(MyHash[options].symbolize_keys)

    opts[:tags] = tags
    opts[:agg] = aggregations

    _put("gauge.#{name}", opts[:tags], value, opts[:agg], opts[:agg_freq], @config[:sample_rate], opts[:namespace])
  end


  # Flush metrics buffer
  def flush_metrics
    flush
  end

  # Adds a new metric to the buffer
  #
  # @private
  # @param metric [String] Name of the metric, ex: `response_time`
  # @param value [Numeric] Value of the metric
  # @param [Hash] options The options to apply to the metric
  # @param options tags [Hash] Tags to associate to the metric
  # @param options agg [Array<String>] List of aggregations to be applied by Statful
  # @param options agg_freq [Integer] Aggregation frequency in seconds
  # @param options sample_rate [Integer] Sampling rate, between: (1-100)
  # @param options namespace [String] Namespace of the metric
  # @param options timestamp [Integer] Timestamp of the metric
  def put(metric, value, options = {})
    tags = @config[:tags]
    tags = tags.merge(options[:tags]) unless options[:tags].nil?

    agg = options[:agg].nil? ? [] : options[:agg]

    sample_rate = options[:sample_rate].nil? ? 100 : options[:sample_rate]
    namespace = options[:namespace].nil? ? 'application' : options[:namespace]

    _put(metric, tags, value, agg, options[:agg_freq], sample_rate, namespace, options[:timestamp])
  end

  private

  attr_accessor :buffer
  attr_accessor :logger

  # Adds a new metric to the buffer
  #
  # @private
  # @param metric [String] Name of the metric, ex: `response_time`
  # @param value [Numeric] Value of the metric
  # @param tags [Hash] Tags to associate to the metric
  # @param agg [Array<String>] List of aggregations to be applied by Statful
  # @param agg_freq [Integer] Aggregation frequency in seconds
  # @param sample_rate [Integer] Sampling rate, between: (1-100)
  # @param namespace [String] Namespace of the metric
  # @param timestamp [Integer] Timestamp of the metric
  def _put(metric, tags, value, agg = [], agg_freq = 10, sample_rate = 100, namespace = 'application', timestamp = nil)
    metric_name = "#{namespace}.#{metric}"
    sample_rate_normalized = sample_rate / 100
    timestamp = Time.now.to_i if timestamp.nil?

    @config.has_key?(:app) ? merged_tags = tags.merge({:app => @config[:app]}) : merged_tags = tags

    if Random.new.rand(1..100)*0.01 <= sample_rate_normalized
      flush_line = merged_tags.keys.inject(metric_name) { |previous, tag|
        "#{previous},#{tag.to_s}=#{merged_tags[tag]}"
      }

      flush_line += " #{value} #{timestamp}"

      unless agg.empty?
        agg.push(agg_freq)
        flush_line += " #{agg.join(',')}"
      end

      flush_line += sample_rate ? " #{sample_rate}" : ''

      put_raw(flush_line)
    end
  end

  # Add raw metrics directly into the flush buffer
  #
  # @private
  # @param metric_lines
  def put_raw(metric_lines)
    @buffer.push(metric_lines)
    if @buffer.size >= @config[:flush_size]
      flush
    end
  end

  # Flushed the metrics to the Statful via UDP
  #
  # @private
  def flush
    unless @buffer.empty?
      message = @buffer.to_a.join('\n')

      # Handle socket errors by just logging if we have a logger instantiated
      # We could eventually save the buffer state but that would require us to manage the buffer size etc.
      begin
        @logger.debug("Flushing metrics: #{message}") unless @logger.nil?

        if !@config.has_key?(:dryrun) || !@config[:dryrun]
          transport_send(message)
        end
      rescue SocketError => ex
        @logger.debug("Statful: #{ex} on #{@config[:host]}:#{@config[:port]}") unless @logger.nil?
        false
      ensure
        @buffer.clear
      end
    end
  end

  # Delegate flushing messages to the proper transport
  #
  # @private
  # @param message
  def transport_send(message)
    case @config[:transport]
      when 'http'
        http_transport(message)
      when 'udp'
        udp_transport(message)
      else
        @logger.debug("Failed to flush message due to invalid transport: #{@config[:transport]}") unless @logger.nil?
    end
  end


  # Sends message via http transport
  #
  # @private
  # @param message
  # :nocov:
  def http_transport(message)
    headers = {
      'Content-Type' => 'application/json',
      'M-Api-Token' => @config[:token]
    }

    @pool.post do
      begin
        response = @http.send_request('PUT', '/tel/v2.0/metrics', message, headers)

        if response.code != '201'
          @logger.debug("Failed to flush message via http with: #{response.code} - #{response.msg}") unless @logger.nil?
        end
      rescue StandardError => ex
        @logger.debug("Statful: #{ex} on #{@config[:host]}:#{@config[:port]}") unless @logger.nil?
        false
      end
    end
  end

  # Sends message via udp transport
  #
  # @private
  # @param message
  # :nocov:
  def udp_transport(message)
    udp_socket.send(message)
  end

  # Return a new or existing udp socket
  #
  # @private
  # :nocov:
  def udp_socket
    Thread.current[:statful_socket] ||= UDPSocket.new(Addrinfo.udp(@config[:host], @config[:port]).afamily)
  end

  # Custom Hash implementation to add a symbolize_keys method
  #
  # @private
  class MyHash < Hash
    # Recursively symbolize an Hash
    #
    # @return [Hash] the symbolized hash
    def symbolize_keys
      symbolize = lambda do |h|
        Hash === h ?
          Hash[
            h.map do |k, v|
              [k.respond_to?(:to_sym) ? k.to_sym : k, symbolize[v]]
            end
          ] : h
      end

      symbolize[self]
    end
  end

  # Custom Queue implementation to add a to_a method
  #
  # @private
  class MyQueue < Queue
    # Transform Queue to Array
    #
    # @return [Array] queue as array
    def to_a
      [].tap { |array| array << pop until empty? }
    end
  end
end
