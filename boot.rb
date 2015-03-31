require 'sneakers'
require 'redis'
require 'json'

Sneakers.configure(prefetch: 1)
Sneakers.logger.level = Logger::INFO

class Processor
  include Sneakers::Worker
  from_queue :calc

  REDIS = Redis.new

  def work(json_msg)
    msg = JSON.parse(json_msg)
    puts msg
    REDIS.set(msg['id'], 'calculating')
    puts 'calculating'
    sleep 3
    REDIS.set(msg['id'], 'calculated')
    puts 'calculated'
    ack! # Tell RabbitMQ that the message is successfully handled.
  end
end
