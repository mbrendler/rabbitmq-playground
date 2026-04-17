// c++ -Wall -Wextra -Wpedantic -I/opt/homebrew/include -L/opt/homebrew/lib
// -lrabbitmq -o publisher-c++ publisher-c++.cpp

#include <rabbitmq-c/amqp.h>
#include <rabbitmq-c/ssl_socket.h>
#include <rabbitmq-c/tcp_socket.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>

class RmqPublisher {
public:
  explicit RmqPublisher(const char *url) : m_url(strdup(url)) {
    amqp_default_connection_info(&m_conn_info);
    if (!m_url) {
      m_error = "allocating URL string";
      return;
    }
    int rc = amqp_parse_url(m_url, &m_conn_info);
    if (rc != AMQP_STATUS_OK) {
      m_error = "parsing URL";
      return;
    }

    connect();
  }
  RmqPublisher(const RmqPublisher &) = delete;
  RmqPublisher &operator=(const RmqPublisher &) = delete;
  RmqPublisher(RmqPublisher &&) = delete;
  RmqPublisher &operator=(RmqPublisher &&) = delete;
  ~RmqPublisher() {
    free(m_url);
    // if (m_conn_info.ssl) {
    //   amqp_uninitialize_ssl_library();
    // }
    if (!m_conn) {
      return;
    }
    amqp_channel_close(m_conn, 1, AMQP_REPLY_SUCCESS);
    amqp_connection_close(m_conn, AMQP_REPLY_SUCCESS);
    amqp_destroy_connection(m_conn);
  }

  std::string create_exchange(const char *exchange) {
    if (!m_conn) {
      return m_error;
    }

    amqp_exchange_declare(m_conn, 1, amqp_cstring_bytes(exchange),
                          amqp_cstring_bytes("topic"),
                          /*passive=*/0,
                          /*durable=*/1,
                          /*auto_delete=*/0,
                          /*internal=*/0, amqp_empty_table);
    amqp_rpc_reply_t reply = amqp_get_rpc_reply(m_conn);
    if (reply.reply_type != AMQP_RESPONSE_NORMAL) {
      return std::string("Declaring exchange: ") +
             amqp_error_string2(reply.library_error);
    }

    return "";
  }

  std::string publish(const char *message, const char *routing_key,
                      const char *exchange) {
    if (!m_conn) {
      return m_error;
    }

    amqp_bytes_t message_bytes = amqp_cstring_bytes(message);
    amqp_bytes_t routing_key_bytes = amqp_cstring_bytes(routing_key);
    amqp_bytes_t exchange_bytes = amqp_cstring_bytes(exchange);
    const int rc =
        amqp_basic_publish(m_conn, 1, exchange_bytes, routing_key_bytes, 1, 0,
                           NULL, message_bytes);
    if (rc != AMQP_STATUS_OK) {
      return std::string("Publishing message: ") + amqp_error_string2(rc);
    }
#ifdef CHECK_PUBLISHER_CONFIRM
    amqp_rpc_reply_t reply = amqp_get_rpc_reply(m_conn);
    if (reply.reply_type != AMQP_RESPONSE_NORMAL) {
      return std::string("Waiting for publisher confirm: ") +
             amqp_error_string2(reply.library_error);
    }

    amqp_frame_t frame;
    amqp_simple_wait_frame(m_conn, &frame);
    if (frame.frame_type == AMQP_FRAME_METHOD) {
      if (frame.payload.method.id == AMQP_BASIC_NACK_METHOD) {
        return "Message was nack'd by the broker";
      } else if (frame.payload.method.id == AMQP_CHANNEL_CLOSE_METHOD) {
        return "Channel was closed by the broker";
      }
    }
#endif

    return "";
  }

  const std::string &error() const { return m_error; }

private:
  void connect() {
    m_conn = amqp_new_connection();
    if (!m_conn) {
      m_error = "creating connection";
      return;
    }
    amqp_socket_t *socket = nullptr;
    if (m_conn_info.ssl) {
      socket = amqp_ssl_socket_new(m_conn);
    } else {
      socket = amqp_tcp_socket_new(m_conn);
    }

    if (!socket) {
      m_error = "creating TCP socket";
      amqp_destroy_connection(m_conn);
      m_conn = nullptr;
      return;
    }
    if (m_conn_info.ssl) {
      amqp_ssl_socket_set_verify_peer(socket, 0);
      amqp_ssl_socket_set_verify_hostname(socket, 0);
    }

    const int rc = amqp_socket_open(socket, m_conn_info.host, m_conn_info.port);
    if (rc != AMQP_STATUS_OK) {
      m_error = "opening TCP socket";
      amqp_destroy_connection(m_conn);
      m_conn = nullptr;
      return;
    }

    amqp_rpc_reply_t ret = amqp_login(m_conn, m_conn_info.vhost, 0, 131072, 0,
                                      AMQP_SASL_METHOD_PLAIN, m_conn_info.user,
                                      m_conn_info.password);
    if (ret.reply_type != AMQP_RESPONSE_NORMAL) {
      m_error =
          "Logging in: " + std::string(amqp_error_string2(ret.library_error));
      amqp_connection_close(m_conn, AMQP_REPLY_SUCCESS);
      amqp_destroy_connection(m_conn);
      m_conn = nullptr;
      return;
    }

    amqp_channel_open(m_conn, 1);
    ret = amqp_get_rpc_reply(m_conn);
    if (ret.reply_type != AMQP_RESPONSE_NORMAL) {
      m_error =
          "Open channel: " + std::string(amqp_error_string2(ret.library_error));
      amqp_connection_close(m_conn, AMQP_REPLY_SUCCESS);
      amqp_destroy_connection(m_conn);
      m_conn = nullptr;
      return;
    }

#ifdef CHECK_PUBLISHER_CONFIRM
    amqp_confirm_select(m_conn, 1);
    amqp_rpc_reply_t reply = amqp_get_rpc_reply(m_conn);
    if (reply.reply_type != AMQP_RESPONSE_NORMAL) {
      m_error = "Enabling publisher confirms: " +
                std::string(amqp_error_string2(reply.library_error));
      amqp_connection_close(m_conn, AMQP_REPLY_SUCCESS);
      amqp_destroy_connection(m_conn);
      m_conn = nullptr;
      return;
    }
#endif
  }

  std::string m_error;
  char *m_url = nullptr;
  amqp_connection_info m_conn_info;
  amqp_connection_state_t m_conn = nullptr;
};

int main(int argc, char *argv[]) {
  const char *url = getenv("RABBITMQ_URL");
  if (!url) {
    url = "amqp://127.0.0.1:5672";
  }

  RmqPublisher publisher(url);
  if (publisher.error().size() > 0) {
    fprintf(stderr, "%s\n", publisher.error().c_str());
    return 1;
  }

  const char *message = "Hello, world!";
  if (argc > 1) {
    message = argv[1];
  }

  std::string error = publisher.create_exchange("playground.a-exchange");
  if (error.size() > 0) {
    fprintf(stderr, "%s\n", error.c_str());
    return 1;
  }

  error = publisher.publish(message, "playground.a-routing-key",
                            "playground.a-exchange");
  if (error.size() > 0) {
    fprintf(stderr, "%s\n", error.c_str());
    return 1;
  }

  return 0;
}
