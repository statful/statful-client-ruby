require 'socket'
require 'delegate'

# Telemetron Client Instance
#
# @attr_reader config [Hash] Current client config
class TelemetronClient
  attr_reader :config

  # Initialize the client
  #
  # @param [Hash] config Client bootstrap configuration
  # @option config [String] :host Destination host
  # @option config [String] :port Destination port
  # @option config [String] :prefix Global metric prefix *required*
  # @option config [String] :app Global metric app tag
  # @option config [TrueClass/FalseClass] :dry Enable dry-run mode
  # @option config [Object] :logger Logger instance that supports debug (if dryrun is enabled) and error methods
  # @option config [Hash] :tags Global list of metric tags
  # @option config [Integer] :sample_rate Global sample rate (as a percentage), between: (1-100)
  # @option config [Integer] :flush_size Buffer flush upper size limit
  # @return [Object] The Telemetron client
  def initialize(config = {})
    user_config = MyHash[config].symbolize_keys

    if !user_config.has_key?(:prefix)
      raise ArgumentError.new('Prefix is undefined')
    end

    if user_config.has_key?(:sample_rate) && !user_config[:sample_rate].between?(1, 100)
      raise ArgumentError.new('Sample rate is not within range (1-100)')
    end

    default_config = {
      :host => '127.0.0.1',
      :port => 2013,
      :tags => {},
      :sample_rate => 100,
      :flush_size => 10
    }

    @config = default_config.merge(user_config)
    @logger = @config[:logger]
    @buffer = []

    self
  end

  # Sends a timer
  #
  # @param name [String] Name of the timer
  # @param value [Numeric] Value of the metric
  # @param [Hash] options The options to apply to the metric
  # @option options [Hash] :tags Tags to associate to the metric
  # @option options [Array<String>] :agg List of aggregations to be applied by the Telemetron
  # @option options [Integer] :agg_freq Aggregation frequency in seconds
  # @option options [String] :namespace Namespace of the metric
  def timer(name, value, options = {})
    opts = {
      :tags => {:unit => 'ms'},
      :agg => %w(avg p90 count count_ps),
      :agg_freq => 10,
      :namespace => 'application'
    }.merge(MyHash[options].symbolize_keys)

    put("timer.#{name}", opts[:tags], value, opts[:agg], opts[:agg_freq], @config[:sample_rate], opts[:namespace])
  end

  # Sends a counter
  #
  # @param name [String] Name of the counter
  # @param value [Numeric] Increment/Decrement value, this will be truncated with `to_int`
  # @param [Hash] options The options to apply to the metric
  # @option options [Hash] :tags Tags to associate to the metric
  # @option options [Array<String>] :agg List of aggregations to be applied by the Telemetron
  # @option options [Integer] :agg_freq Aggregation frequency in seconds
  # @option options [String] :namespace Namespace of the metric
  def counter(name, value, options = {})
    opts = {
      :tags => {},
      :agg => %w(sum count count_ps),
      :agg_freq => 10,
      :namespace => 'application'
    }.merge(MyHash[options].symbolize_keys)

    put("counter.#{name}", opts[:tags], value.to_i, opts[:agg], opts[:agg_freq], @config[:sample_rate], opts[:namespace])
  end

  # Sends a gauge
  #
  # @param name [String] Name of the gauge
  # @param value [Numeric] Value of the metric
  # @param [Hash] options The options to apply to the metric
  # @option options [Hash] :tags Tags to associate to the metric
  # @option options [Array<String>] :agg List of aggregations to be applied by the Telemetron
  # @option options [Integer] :agg_freq Aggregation frequency in seconds
  # @option options [String] :namespace Namespace of the metric
  def gauge(name, value, options = {})
    opts = {
      :tags => {},
      :agg => %w(last),
      :agg_freq => 10,
      :namespace => 'application'
    }.merge(MyHash[options].symbolize_keys)

    put("gauge.#{name}", opts[:tags], value, opts[:agg], opts[:agg_freq], @config[:sample_rate], opts[:namespace])
  end

  # Flush metrics buffer
  def flush_metrics
    flush
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
  # @param agg [Array<String>] List of aggregations to be applied by the Telemetron
  # @param agg_freq [Integer] Aggregation frequency in seconds
  # @param sample_rate [Integer] Sampling rate, between: (1-100)
  # @param namespace [String] Namespace of the metric
  def put(metric, tags, value, agg = [], agg_freq = 10, sample_rate = nil, namespace = 'application')
    metric_name = "#{@config[:prefix]}.#{namespace}.#{metric}"
    sample_rate_normalized = sample_rate / 100

    @config.has_key?(:app) ?
      merged_tags = tags.merge({:app => @config[:app]}).merge(@config[:tags]) :
      merged_tags = tags.merge(@config[:tags])

    if Random.new.rand(1..100)*0.01 <= sample_rate_normalized
      flush_line = merged_tags.keys.inject(metric_name) { |previous, tag|
        "#{previous},#{tag.to_s}=#{merged_tags[tag]}"
      }

      flush_line += " #{value} #{Time.now.to_i}"

      if !agg.empty?
        agg.push(agg_freq)
        flush_line += " #{agg.join(',')}"
        flush_line += sample_rate ? " #{sample_rate}" : ''
      end

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

  # Flushed the metrics to the Telemetron via UDP
  #
  # @private
  def flush
    if !@buffer.empty?
      message = @buffer.join('\n')

      # Handle socket errors by just logging if we have a logger instantiated
      # We could eventually save the buffer state but that would require us to manage the buffer size etc.
      begin
        if @config.has_key?(:dryrun) && @config[:dryrun]
          @logger.debug("Flushing metrics: #{message}") unless @logger.nil?
        else
          socket.send(message)
        end
      rescue SocketError => ex
        @logger.error("Telemetron: #{ex} on #{@config[:host]}:#{@config[:port]}") unless @logger.nil?
        false
      ensure
        @buffer.clear
      end
    end
  end


  # Create a new UDP socket
  #
  # @private
  # :nocov:
  def socket
    Thread.current[:telemetron_socket] ||= UDPSocket.new(Addrinfo.udp(@config[:host], @config[:port]).afamily)
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
end

