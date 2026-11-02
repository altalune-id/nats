FROM nats:2.15.2-alpine3.22@sha256:823e7f1d6d8ffe3b30dbd73d4a06bbb939acf94929f7fdf224404da7a05bafb5

COPY nats-server.conf /etc/nats/nats-server.conf
COPY --chmod=755 require-passwords.sh /usr/local/bin/require-passwords.sh

EXPOSE 4222 8222

ENTRYPOINT ["require-passwords.sh"]
CMD ["nats-server", "--config", "/etc/nats/nats-server.conf"]
