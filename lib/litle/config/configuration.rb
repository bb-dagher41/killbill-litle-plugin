require 'logger'

module Killbill::Litle
  mattr_reader :logger
  mattr_reader :config
  mattr_reader :gateway
  mattr_reader :initialized
  mattr_reader :test

  def self.initialize!(config_file='litle.yml', logger=Logger.new(STDOUT))
    @@logger = logger

    @@config = Properties.new(config_file)
    @@config.parse!
    @@test = @@config[:litle][:test]

    @@gateway = Killbill::Litle::Gateway.instance
    @@gateway.configure(@@config[:litle])

    if defined?(JRUBY_VERSION)
      # See https://github.com/jruby/activerecord-jdbc-adapter/issues/302
      require 'jdbc/mysql'
      Jdbc::MySQL.load_driver(:require) if Jdbc::MySQL.respond_to?(:load_driver)
    end

    ActiveRecord::Base.establish_connection(@@config[:database])

    @@initialized = true
  end
end