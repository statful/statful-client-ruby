# statful-client-ruby

Statful ruby client.

TODO

## Development

Everything has been developed and tested using:

```
ruby 2.2.3p173 (2015-08-18 revision 51636) [x86_64-darwin14]
```

It is highly recommended that you use a ruby version manager to manage your local env - we suggest [RVM](https://rvm.io/).

### Installation

It uses [bundler](http://bundler.io/) to install all dev dependencies:

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
