# altalune-nats

NATS JetStream image for Altalune Go services built on the Altalune standard template: the official `nats` image, pinned by digest, with one
config file. One server is shared by every app, and each app gets its own NATS account. No secret lives in this repo; each account's
password comes from the environment at start.

## Image

`ghcr.io/altalune-id/nats`

| Tag           | Built from          |
| ------------- | ------------------- |
| `edge`        | every push to main  |
| `<short-sha>` | every push to main  |
| `X.Y.Z`, `X.Y`| a `vX.Y.Z` git tag  |

Base: `nats:2.15.0-alpine3.22` pinned by sha256. Dependabot opens a PR when a newer base or action
version exists.

## Configuration

| Setting                 | Value                                                              |
| ----------------------- | ------------------------------------------------------------------ |
| `ALTEMPL_NATS_PASSWORD` | required, at least 16 characters; user `altempl`, account ALTEMPL |
| `OPENWA_NATS_PASSWORD`  | required, at least 16 characters; user `openwa`, account OPENWA   |
| `YASAKU_NATS_PASSWORD`  | required, at least 16 characters; user `yasaku`, account YASAKU   |
| client port             | 4222                                                               |
| monitoring port         | 8222 (`/healthz?js-enabled-only=true`)                             |
| JetStream storage       | `/data`, file store capped at 4G; each account capped at 1G        |

The server refuses to start while any password is unset, empty or shorter than 16 characters: NATS itself would accept an
empty password as a valid login.

Accounts isolate apps completely. Every template app uses the same stream names (`WORK`, `DLQ`, `BROADCAST`) and job
subjects, so two apps must never share an account: they would consume each other's jobs. Each app reserves about 576 MiB of
its account's quota when it creates its streams.

## Adding an app

1. Add an account to `nats-server.conf` with its own `<APP>_NATS_PASSWORD`, `jetstream { max_file: 1G, max_mem: 16M }`, and
   raise `max_file_store` if the accounts would exceed it.
2. Add the user to `users` in `scripts/smoke.sh`.
3. Release, set the new variable on the NATS service, then redeploy it. Every app reconnects on its own after the restart.

## Deploy (Railway)

1. New service from image `ghcr.io/altalune-id/nats:<tag>`.
2. Attach a volume at `/data`, at least 5 GB. Without it every redeploy drops queued jobs and the DLQ.
3. Set every `<APP>_NATS_PASSWORD` to a long random string (`openssl rand -hex 32`).
4. Private networking only: no public domain, no TCP proxy.
5. Stop timeout about 20s.

On each Go service (Altalune template queue config, with its own prefix and user):

```
ALT_QUEUE_ENABLED=true
ALT_QUEUE_URL=nats://<nats-service>.railway.internal:4222
ALT_QUEUE_USER=altempl
ALT_QUEUE_PASSWORD=${{<nats-service>.ALTEMPL_NATS_PASSWORD}}
```

A service built before `queue.user` existed can carry the credentials in the URL instead, with no token:
`nats://altempl:<password>@<nats-service>.railway.internal:4222`.

## Local check

```
bash scripts/smoke.sh            # ENGINE=podman for podman
```

It checks: no start without the passwords or with an empty one, JetStream on `/data`, a missing or wrong password is
rejected, every account user is accepted, and a message published in one account never reaches another. CI runs the same
script before publishing.

## Release

Tag `vX.Y.Z` (match the NATS version, e.g. `v2.15.0`), push the tag.
