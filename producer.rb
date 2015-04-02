require 'sneakers'
require 'redis'
require 'json'

def main
  Sneakers.configure
  Sneakers.logger.level = Logger::INFO

  puts "publish: #{ARGV[0]}"
  id = JSON.parse(ARGV[0])['id']
  redis = Redis.new
  redis.set(id, 'pending')

  Sneakers::Publisher.new.publish(ARGV[0], to_queue: :calc)
  puts 'sent'

  status = redis.get(id)
  puts "status: #{status}"
  while status != 'calculated'
    sleep 0.5
    status = redis.get(id)
    puts "status: #{status}"
  end
  puts 'done'
end

main if __FILE__ == $PROGRAM_NAME
