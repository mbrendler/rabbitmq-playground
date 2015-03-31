require 'sneakers'

def main
  Sneakers.configure
  Sneakers.logger.level = Logger::INFO
  puts "publish: #{ARGV[0]}"
  Sneakers::Publisher.new.publish(ARGV[0], host: 'localhost', to_queue: :calc)
  puts 'done'
end

main if __FILE__ == $PROGRAM_NAME
