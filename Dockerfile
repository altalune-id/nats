FROM nats:2.15.3-alpine3.22@sha256:558394a23dd3c36f2d3a64b51865fd09908010e80a542cea5e75c2af543ed62a

COPY nats-server.conf /etc/nats/nats-server.conf
COPY --chmod=755 require-passwords.sh /usr/local/bin/require-passwords.sh

EXPOSE 4222 8222

ENTRYPOINT ["require-passwords.sh"]
CMD ["nats-server", "--config", "/etc/nats/nats-server.conf"]
