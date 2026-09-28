# altalune-nats

NATS JetStream image for Altalune Go services built on the Altalune standard template: the official `nats` image, pinned by digest, with one
config file. No secret lives in this repo; the token comes from the environment at start.

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

| Setting            | Value                                         |
| ------------------ | --------------------------------------------- |
| `NATS_TOKEN`       | required; the server refuses to start without |
| client port        | 4222                                          |
| monitoring port    | 8222 (`/healthz?js-enabled-only=true`)        |
| JetStream storage  | `/data`, file store capped at 1G              |

## Deploy (Railway)

1. New service from image `ghcr.io/altalune-id/nats:<tag>`.
2. Attach a volume at `/data`, at least 1 GB. Without it every redeploy drops queued jobs and the DLQ.
3. Set `NATS_TOKEN` to a long random string.
4. Private networking only: no public domain, no TCP proxy.
5. Stop timeout about 20s.

On the Go service (Altalune template queue config):

```
ALT_QUEUE_ENABLED=true
ALT_QUEUE_URL=nats://<nats-service>.railway.internal:4222
ALT_QUEUE_TOKEN=${{<nats-service>.NATS_TOKEN}}
```

## Local check

```
bash scripts/smoke.sh            # ENGINE=podman for podman
```

It checks: no start without a token, JetStream on `/data`, a missing or wrong token is rejected, the
right token is accepted. CI runs the same script before publishing.

## Release

Tag `vX.Y.Z` (match the NATS version, e.g. `v2.15.0`), push the tag.
