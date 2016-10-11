Statful Client for Ruby
==============

[![Build Status](https://travis-ci.org/statful/statful-client-ruby.svg?branch=master)](https://travis-ci.org/statful/statful-client-ruby)
[![Gem Version](https://badge.fury.io/rb/statful-client.svg)](https://badge.fury.io/rb/statful-client)

Staful client for Ruby. This client is intended to gather metrics and send them to Statful.

## Table of Contents

* [Supported Versions of Ruby](#supported-versions-of-ruby)
* [Installation](#installation)
* [Quick Start](#quick-start)
* [Examples](#examples)
* [Reference](#reference)
* [Development](#development)
* [Authors](#authors)
* [License](#license)

## Supported Versions of Ruby

| Tested Ruby versions  |
|:---|
|  `2.1.8`, `2.2.4`, `2.3.0` |

## Installation

```bash
$ gem install statful-client
```

## Quick start

After installing Statful Client you are ready to use it. The quickest way is to do the following:

```ruby
require 'statful-client'

config = {
  :transport => 'http',
  :token => 'test_token',
}

statful = StatfulClient.new(config)
```

> **IMPORTANT:** This configuration uses the default **host** and **port**. You can learn more about configuration in [Reference](#reference).

## Examples

You can find here some useful usage examples of the Statful Client. In the following examples is assumed you have already installed and included Statful Client in your project.

### UDP Configuration

Creates a simple UDP configuration for the client.

```ruby
require 'statful-client'

config = {
  :transport => 'udp',
  :host => 'in_premises_statful_relay',
  :tags => { :test_tag => 'test_tag_value' },
  :flush_size => 10
}

statful = StatfulClient.new(config)
```

> **IMPORTANT:** UDP transport is only available by using an in-premises [statful-relay](https://github.com/statful/statful-relay).

### HTTP Configuration

Creates a simple HTTP API configuration for the client.

```ruby
require 'statful-client'

config = {
  :transport => 'http',
  :token => 'test_token',
  :tags => { :test_tag => 'test_tag_value' },
  :flush_size => 10
}

statful = StatfulClient.new(config)
```

### Logger configuration

Creates a simple client configuration and adds your favourite logger to the client.

**Just assure that logger object supports, at least, warn, debug and error methods**.

```ruby
require 'statful-client'
require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

config = {
  :transport => 'http',
  :token => 'test_token',
  :tags => { :test_tag => 'test_tag_value' },
  :logger => logger,
  :flush_size => 10
}

statful = StatfulClient.new(config)
```

### Defaults Configuration Per Method

Creates a configuration for the client with custom default options per method.

```ruby
require 'statful-client'

config = {
  :transport => 'http',
  :token => 'test_token',
  :tags => { :test_tag => 'test_tag_value' },
  :flush_size => 10,
  :defaults => {
    :counter => { :agg => %w(avg), :aggFreq => 180 },
    :gauge => { :agg => %w(first), :aggFreq => 180 },
    :timer => { :tags => { :cluster => 'test' }, :agg => %s(count), :aggFreq => 180 }
  }
}

statful = StatfulClient.new(config)
```

### Mixed Complete Configuration

Creates a mixed configuration for possible real scenario.

```ruby
require 'statful-client'
require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

config = {
  :transport => 'http',
  :token => 'test_token',
  :tags => { :test_tag => 'test_tag_value' },
  :dryrun => true,
  :logger => logger,
  :flush_size => 10,
  :namespace => 'my_test_app',
  :defaults => {
    :counter => { :agg => %w(avg), :aggFreq => 180 },
    :gauge => { :agg => %w(first), :aggFreq => 180 },
    :timer => { :tags => { :cluster => 'test' }, :agg => %s(count), :aggFreq => 180 }
  }
}

statful = StatfulClient.new(config)
```

### Add metrics

Creates a simple client configuration and use it to send some metrics.

```ruby
require 'statful-client'

config = {
  :transport => 'http',
  :token => 'test_token',
  :tags => { :test_tag => 'test_tag_value' },
  :flush_size => 1
}

statful = StatfulClient.new(config)

# Send three different metrics (timer, counter and gauge)
statful.timer("test_timer", 100)
statful.counter("test_counter", 1)
statful.gauge("test_gauge", 33)

# Send a timer with custom aggregations
statful.timer("test_timer", 100, { :agg => %w(p50), :aggFreq => 60 })

# Send a timer with custom tags
statful.timer("test_timer", 100, { :tags => {:host => 'test_host', :status => 'SUCCESS' } }
```

## Reference

Detailed reference if you want to take full advantage from Statful.

### Global configuration

The custom options that can be set on config param are detailed below.

| Option | Description | Type | Default | Required |
|:---|:---|:---|:---|:---|
| _host_ | Defines the host name to where the metrics should be sent. | `String` | `api.statful.com` | **NO** |
| _port_ | Defines the port. | `Integer` | `443` | **NO** |
| _transport_ | Defines the transport layer to be used to send metrics.<br><br> **Valid Transports:** `udp, http` | `String` | `http` | **NO** |
| _timeout_ | Defines the timeout for the transport layers in **miliseconds**. | `Integer` | `2000` | **NO** |
| _token_ | Defines the token to be used. | `String` | **none** | **YES if using HTTP transport** |
| _app_ | Defines the application global name. If specified sets a global tag `app=setValue`. | `String` | **none** | **NO** |
| _dryrun_ | Defines if metrics should be output to the logger instead of being sent. | `Boolean` | `false` | **NO** |
| _logger_ | Defines logger object. | `Object` | **none** | **NO** |
| _tags_ | Defines the global tags. | `Hash` | `{}` | **NO** |
| _sample_rate_ | Defines the rate sampling. **Should be a number between [1, 100]**. | `Integer` | `100` | **NO** |
| _flush_size_ | Defines the maximum buffer size before performing a flush. | `Integer` | `5` | **NO** |
| _thread_pool_size_ | Defines the maximum thread pool size. | `Integer` | `5` | **NO** |
| _namespace_ | Defines the global namespace. | `String` | `application` | **NO** |
| _default_ | Object to set methods options. | `Object` | `{}` | **NO** |

### Methods

```ruby
- staful.counter('myCounter', 1, { :agg => ['sum'] });
- staful.gauge('myGauge', 10, { :tags => { :host => 'localhost' } });
- staful.timer('myTimer', 200, { :namespace => 'sandbox' });
- staful.put('myCustomMetric', 200, { :timestamp => '1471519331' });
```

| Option | Description | Type | Default for Counter | Default for Gauge | Default for Timer | Default for Put |
|:---|:---|:---|:---|:---|:---|:---|:---|
| _agg_ | Defines the aggregations to be executed. These aggregations are merged with the ones configured globally, including method defaults.<br><br> **Valid Aggregations:** `avg, count, sum, first, last, p90, p95, min, max` | `Array` | `['avg', 'p90']` | `[last]` | `['avg', 'p90', 'count']` | `[]` |
| _aggFreq_ | Defines the aggregation frequency in **seconds**. It overrides the global aggregation frequency configuration.<br><br> **Valid Aggregation Frequencies:** `10, 30, 60, 120, 180, 300` | `Integer` | `10` | `10` | `10` | `10` |
| _namespace_ | Defines the namespace of the metric. It overrides the global namespace configuration. | `String` | `application` | `application` | `application` | `application` |
| _tags_ | Defines the tags of the metric. These tags are merged with the ones configured globally, including method defaults. | `Object` | `{}` | `{}` | `{ unit: 'ms' }` | `{}` |
| _timestamp_ | Defines the timestamp of the metric. This timestamp is a **POSIX/Epoch** time in **seconds**. | `String` | `current timestamp` | `current timestamp` | `current timestamp` | `current timestamp` |

## Development

### Dependencies

Use bundle to install all dev dependencies:

```
$ bundle install
```

### Tests

It uses [rspec](http://rspec.info/) and [minitest](http://docs.seattlerb.org/minitest/) to specify the unit tests suite.

There's a rake task which runs the specs:

```
$ rake spec
```

### Build

Use gem to build a gem according to the spec if required:

```
$ gem build statful-ruby.gemspec
```

### Docs

It uses [yard](http://yardoc.org/) to generate documentation.

There's a rake task which generates the doc directory with the output:

```
$ rake yard
```

## Authors

[Mindera - Software Craft](https://github.com/Mindera)

## License

Statful Ruby Client is available under the MIT license. See the [LICENSE](https://raw.githubusercontent.com/statful/statful-client-ruby/master/LICENSE) file for more information.
