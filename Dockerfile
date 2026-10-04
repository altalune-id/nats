FROM nats:2.15.0-alpine3.22@sha256:ac8f88a6494bffc2c2a5289a0ca61cb28a9145c11ba5677cf24265d07f46d8d4

COPY nats-server.conf /etc/nats/nats-server.conf
COPY --chmod=755 require-passwords.sh /usr/local/bin/require-passwords.sh

EXPOSE 4222 8222

ENTRYPOINT ["require-passwords.sh"]
CMD ["nats-server", "--config", "/etc/nats/nats-server.conf"]
