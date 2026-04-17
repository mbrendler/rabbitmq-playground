# RabbitMQ playground

```
docker compose up rabbitmq
```

* Ruby

```
bundle install
./consumer.rb
./publisher.rb 'a message' 'another message'
./status queue_name  # show queue status
./proxy.rb  # rabbitmq proxy to prints communication data
```

* C / C++

```
brew install rabbitmq-c

cc -Wall -Wextra -Wpedantic -I/opt/homebrew/include -L/opt/homebrew/lib -lrabbitmq -o publisher-c publisher-c.c
./publisher-c


c++ -Wall -Wextra -Wpedantic -DCHECK_PUBLISHER_CONFIRM=1 -I/opt/homebrew/include -L/opt/homebrew/lib -lrabbitmq -o publisher-c++ publisher-c++.cpp
./publisher-c++
```


Links:

* http://rubybunny.info/articles/queues.html
* http://rubybunny.info/articles/durability.html
* http://rubybunny.info/articles/exchanges.html
* https://github.com/alanxz/rabbitmq-c
* https://alanxz.github.io/rabbitmq-c/docs/0.8.0/
