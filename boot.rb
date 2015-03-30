require 'sneakers'
require 'redis'
require 'json'

Sneakers.configure
Sneakers.logger.level = Logger::INFO

class Processor
  include Sneakers::Worker
  from_queue :logs

  REDIS = Redis.new

  def work(msg)
    err = JSON.parse(msg)
    REDIS.incr("processor:#{err['error']}") if err['type'] == 'error'
    ack!
  end
end
