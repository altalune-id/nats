FROM nats:2.15.1-alpine3.22@sha256:2ae57dfba3063d5e25fecb75256118c0882a1a2d2cf7d0fba17a7c701df956f6

COPY nats-server.conf /etc/nats/nats-server.conf
COPY --chmod=755 require-passwords.sh /usr/local/bin/require-passwords.sh

EXPOSE 4222 8222

ENTRYPOINT ["require-passwords.sh"]
CMD ["nats-server", "--config", "/etc/nats/nats-server.conf"]
