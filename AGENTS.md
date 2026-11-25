# AGENTS.md

Guidance for AI agents (and humans) working in this repo.

This repo is a collection of ready-to-run Docker Compose stacks for **local development only**.
Nothing here is hardened or intended for production. License: WTFPL (`license.txt`).

## Repo layout

One directory per stack; the directory name **is** the stack name.

```
<stack>/
  docker-compose.yml     # always this exact filename
  env.template           # committed, placeholder values only
  .env                   # gitignored, created by copying env.template
  <extra files>          # configs bind-mounted into the container(s)
```

Existing stacks: `elasticsearch` (es + kibana + cert setup), `keycloak`, `minio`, `nats`,
`nuq-postgres`, `playwright`, `postgresql`, `postgresql-pgvector`, `rabbitmq`, `redis`,
`temporal`, `vector`.

Naming quirks that are **deliberate, do not "fix"**:

- `readme.md`, `license.txt` are lowercase.

## Image sourcing

- Docker Hub images are referenced through the `focker.ir/` mirror because Docker Hub returns
  403 (sanctions) from this environment. **Any new Docker Hub image gets the `focker.ir/` prefix.**
- `ghcr.io/...` and `quay.io/...` are reachable and are used as-is (no mirror prefix).
- Tags are not to be bumped as a drive-by change: some stacks pin (`STACK_VERSION`,
  `TEMPORAL_VERSION`, `keycloak:26.4.7`, `vector:0.46.1-alpine`), others float on `latest`.
  Never probe/pull/unpin images just to "tidy" a file.
- `postgresql-pgvector/PGVector.Dockerfile` is the only local build; it layers the `vector`
  extension on top of `focker.ir/postgres:latest`.

## Networking

Everything joins the **external** bridge network `dockernet`. It is *not* created by compose:

```bash
docker network create dockernet      # once per machine
```

Consequences agents must keep in mind:

- Service names are global DNS names on `dockernet`, so each service is named after its stack
  directory (`postgresql`, `redis`, `rabbitmq`, `nuq-postgres`). Keep those names unique across
  the repo: two stacks reusing a service name (or a host port) cannot run at the same time.
- The three postgres stacks (hostname is what other stacks dial; port is the *container* port):

  | dir                   | hostname on dockernet | host port | container port |
  | --------------------- | --------------------- | --------- | -------------- |
  | `postgresql`          | `postgresql`          | 5432      | 5432           |
  | `postgresql-pgvector` | `postgresql-pgvector` | 5433      | 5432           |
  | `nuq-postgres`        | `nuq-postgres`        | 5434      | 5432           |

- Renaming a service changes its DNS name, so every cross-stack consumer must be updated in the
  same change: `keyclock` → `jdbc:postgresql://postgresql:5432/keycloak` (`KC_DB_URL` in both
  `.env` and `env.template`), `temporal` → `POSTGRES_SEEDS=postgresql` (DB `temporal`), and
  firecrawl → `POSTGRES_HOST=nuq-postgres`. Renaming a service recreates containers but leaves
  named volumes intact, so data survives.
- `depends_on` only works inside a stack. Cross-stack ordering is manual: bring up the
  dependency stack first (e.g. `postgresql` before `temporal` and before `keyclock`).
- Credentials must line up across stacks: the `keycloak` and `temporal` databases must exist on
  the `postgresql` stack, and the user/password must match that stack's `.env`.

## Environment variables

- `.env` is gitignored (`.gitignore` = `.env`); **never commit secrets**. `env.template` is
  committed with placeholder values (`user`, `password`, empty for optional settings).
- Every variable referenced by compose must exist in both `.env` and `env.template` — keep the
  key sets identical when adding one.
- Reference variables with braces, always: `${POSTGRES_USER}`. Bare `$VAR` is not used.
- Compose loads `.env` from the **project directory** (the stack dir), so always run from there,
  or pass `-f <stack>/docker-compose.yml` (the file's directory still becomes the project dir).
- A stack only gets an `env.template` if it interpolates at least one variable (`nats`, `redis`,
  `vector` have none).

## Conventions enforced in every compose file

- No top-level `version:` key (Compose Spec), no `container_name:` (keeps project scoping and
  lets stacks be reset/recreated independently).
- `restart: "unless-stopped"` on long-running services. One-shot jobs get no restart policy
  (`elasticsearch`'s `setup`).
- Log rotation on every service:

  ```yaml
  logging:
    driver: "json-file"
    options:
      max-size: "5m"
      max-file: "2"
      compress: "true"
  ```

- Ports are quoted and use the implicit `tcp` protocol, no `/tcp` suffix: `"5432:5432"`.
  They bind `0.0.0.0` on purpose (dev access from other hosts/containers) — host ports are a
  global resource, so check for collisions. Known overlapping ports:
  `keyclock` and `temporal`'s UI both use `8080`. The postgres stacks are spread out
  (5432/5433/5434, see the table above).
- Config files are bind-mounted read-only (`./nats-server.conf:/etc/nats/nats-server.conf:ro`),
  paths relative to the stack dir.
- Persistence uses named volumes with `driver: local`, prefixed per stack
  (`redis_data`, `rabbitmq_data`, `nuq_postgres`, ...). Never copy a volume path blindly: it must
  match the image's data dir (`postgresql` mounts `/var/lib/postgresql`, `nuq-postgres` mounts
  `/var/lib/postgresql/data`).
- Healthchecks are only added when the image actually ships the client (verified by running the
  image, not guessed):
  `pg_isready` (postgres, nuq-postgres), `redis-cli ping`, `rabbitmq-diagnostics -q check_running`,
  `curl` (elasticsearch, kibana), `wget` (vector).
  `nats` is scratch-based (no shell) and `temporal`/`playwright` have no suitable endpoint —
  they intentionally have **no** healthcheck. Do not add shell-based checks to `minio`/
  `keyclock` without first verifying their minimal base image.
- Keep diffs minimal: no reordering of services/environment blocks, no reformatting of
  `elasticsearch`'s `command:` script or other working blocks.

## Common commands

```bash
cd <stack>
docker compose up -d
docker compose ps
docker compose logs -f
docker compose down            # keeps volumes
docker compose down -v         # wipes stack data

# validate a compose file after editing (uses that dir's .env)
docker compose config -q
```

Validate **every** stack you touched with `docker compose config -q`; it catches interpolation
typos and YAML errors without starting containers.

## Adding a new stack

1. `mkdir <name> && cd <name>` — the service inside is named after the directory, and that name
   must be unused on `dockernet`.
2. `docker-compose.yml` with: `focker.ir/`-prefixed image, `restart`, `logging`,
   quoted `ports`, `volumes` under a stack-prefixed named volume, and
   ```yaml
   networks:
     dockernet:
       external: true
       name: "dockernet"
   ```
3. `env.template` (placeholders) for any `${VAR}` used; `cp env.template .env` and fill in.
4. Extra config as a file in the stack dir, mounted `:ro`.
5. `docker compose config -q`, then `up -d`.
6. Mention it in `readme.md` if it needs a note (the readme carries stack-specific caveats).

## Git

- Commit subjects follow `git log` style: `<stack>: <what changed>`, lowercase, imperative —
  e.g. `rabbitmq: fix amqp port mapping, add healthcheck and env template`.
- `.env` files never appear in commits. Changing several stacks? Prefer one commit per stack.

## Known gaps

- `elasticsearch`: filebeat is not wired up (breaking changes upstream; see `readme.md` links).
- `vector`: `vector.json` has empty `sources`/`transforms`/`sinks` — the pipeline is a placeholder;
  extra files go in `vector/resource/` (currently just `.gitkeep`).
- `playwright`: `PORT` is the in-container listen port; nothing is published to the host.
- `keyclock`, `minio` have no healthcheck (see above), so `depends_on: condition: service_healthy`
  cannot be used for them.
