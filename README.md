[![CI](https://github.com/electric-sql/electric/workflows/CI/badge.svg)](https://github.com/electric-sql/electric/actions/workflows/ci.yml)
[![License - Apache 2.0](https://img.shields.io/badge/license-Apache_2.0-blue)](main/LICENSE)
![Status - Alpha](https://img.shields.io/badge/status-alpha-red)
[![Chat - Discord](https://img.shields.io/discord/933657521581858818?color=5969EA&label=discord)](https://discord.gg/B7kHGwDcbj)

<a href="https://electric-sql.com">
  <picture>
    <source media="(prefers-color-scheme: dark)"
        srcset="https://raw.githubusercontent.com/electric-sql/meta/main/identity/ElectricSQL-logo-light-trans.svg"
    />
    <source media="(prefers-color-scheme: light)"
        srcset="https://raw.githubusercontent.com/electric-sql/meta/main/identity/ElectricSQL-logo-black.svg"
    />
    <img alt="ElectricSQL logo"
        src="https://raw.githubusercontent.com/electric-sql/meta/main/identity/ElectricSQL-logo-black.svg"
    />
  </picture>
</a>

# ElectricSQL

Local-first. Electrified.

You develop local-first apps. We provide the cloud sync. Without changing your database or your code.

## What is ElectricSQL?

ElectricSQL is a local-first SQL system that adds active-active replication and reactive queries to SQLite and Postgres. Use it to make local-first apps that feel instant, work offline and sync via the cloud.

## Getting started

- [Quickstart](https://electric-sql.com/docs/usage/quickstart)
- [Examples](https://github.com/electric-sql/examples)
- [Documentation](https://electric-sql.com/docs)

## Repo structure

This repo contains the core backend services that proovide ElectricSQL's cloud sync. It's an Elixir application that integrates with Postgres over logical replication and SQLite via a Protobuf web socket protocol.

See also:

- [electric-sql/typescript-client](https://github.com/electric-sql/typescript-client) Typescript client library for local-first application development
- [electric-sql/cli](https://github.com/electric-sql/cli) command line interface (CLI) tool to manage config and migrations

## Pre-reqs

Docker and [Elixir 1.14 compiled with Erlang 24](https://thinkingelixir.com/install-elixir-using-asdf/).

## Usage

See the [Makefile](./Makefile) for usage. Setup using:

```sh
make deps compile
```

Run the dependencies using:

```sh
make start_dev_env
```

Run the tests:

```sh
make tests
```

And then develop using:

```sh
make shell
```

This runs active-active replication with Postgres over logical replication and exposes a protocol buffers API over web sockets on `localhost:5133`.

For example to write some data into one of the Postgres instances:

```sh
docker exec -it -e PGPASSWORD=password electric_db_a_1 psql -h 127.0.0.1 -U electric -d electric
```

There's a second instance, `electric-db_b_1`, if you want to see data being replicated between them.

Note that you can tear down all the containers with:

```sh
make stop_dev_env
```

### Running the release or docker container

The Electric application is configured using environment variables. Everything that doesn't have a default is required to run.

| Variable                     | Default                     | Description                                                                                                                                                               |
| ---------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ELECTRIC_HOST`              |                             | Host of this electric instance for the reverse connection from Postgres. It has to be accessible from postgres instances listed in the `CONNECTORS`                       |
| `CONNECTORS`                 | `""`                        | Semicolon-separated list of Postgres connection strings for PG instances that will be part of the cluster                                                                 |
|                              |                             |                                                                                                                                                                           |
| `POSTGRES_REPLICATION_PORT`  | `5433`                      | Port for connections from PG instances as replication followers                                                                                                           |
| `STATUS_PORT`                | `5050`                      | Port to expose health and status API endpoint                                                                                                                             |
| `WEBSOCKET_PORT`             | `5133`                      | Port to expose the `/ws` path for the replication over the websocket                                                                                                      |
|                              |                             |                                                                                                                                                                           |
| `OFFSET_STORAGE_FILE`        | `./offset_storage_data.dat` | Path to the file storing the mapping between connected Postgres, Satellite instances, and an internal event log. Should be persisted between Electric restarts.           |
|                              |                             |                                                                                                                                                                           |
| `SATELLITE_AUTH_SIGNING_KEY` | `""`                        | Authentication token signing/validation secret key. See below.                                                                                                            |
| `SATELLITE_AUTH_SIGNING_ISS` | `""`                        | Cluster ID which acts as the issuer for the authentication JWT. See below.                                                                                                |
|                              |                             |                                                                                                                                                                           |
| `GLOBAL_CLUSTER_ID`          |                             | Identifier of the cluster within the Electric cloud. When running locally, you can use any string                                                                         |
| `ELECTRIC_INSTANCE_ID`       |                             | Unique identifier of this Electric instance when running in the cluster. When running locally, you can use any string                                                     |
| `ELECTRIC_REGIONAL_ID`       |                             | Shared identifier for multiple Electric instance that connect to the same DC when running in the cluster. When running locally, you can use any string. Currently unused. |

**Authentication**

By default, in dev mode, electric uses insecure authentication. This just
accepts a user id as the authentication token and authorizes the connection as
that user.

Token based authentication requires a signed JWT token with a `user_id` claim,
and a valid issuer.

To turn on token-based authentication in dev mode and when running in
production, set the following environment variables:

- `SATELLITE_AUTH_SIGNING_KEY` - Some random string used as the HMAC signing
  key. Must be at least 32 bytes long.

- `SATELLITE_AUTH_SIGNING_ISS` - The JWT issuer (the `iss` field in the JWT).

You can generate a valid token using these configuration values by running `mix electric.gen.token`, e.g:

```shell
$ export SATELLITE_AUTH_SIGNING_KEY=00000000000000000000000000000000
$ export SATELLITE_AUTH_SIGNING_ISS=my.electric.server
$ mix electric.gen.token my_user my_other_user
```

The generated token(s) must be passed in the `token` field of the `SatAuthReq`
protocol message.

For them to work, you must run the electric server configured with the same
`SATELLITE_AUTH_SIGNING_KEY` and `SATELLITE_AUTH_SIGNING_ISS` set.

## Migrations

Migrations are semi-automatically managed by the Postgres source. Once Postgres has been initialized by Electric (i.e. Electric had connected to it at least once), you will have two functions available in your SQL:

1. `SELECT electric.migration_version(migration_version);`, where `migration_version` should be a monotonically growing value of your choice
2. `CALL electric.electrify(table_name);`, where `table_name` is a string containing a schema-qualified name of the table you want electrified.

When you want to do a migration (i.e. create a table), you need to run the `electric.migration_version` at the beginning of the transaction, and `electric.electrify` for every new table. Electrified tables and changes to them
will reach the clients and be created there as well. For example:

```sql
BEGIN;
SELECT electric.migration_version('1_version');
CREATE TABLE public.mtable1 (id uuid PRIMARY KEY);
CALL electric.electrify('public.mtable1');
COMMIT;
```

## OSX

Note that if, when running on OSX, you get errors like:

```
could not connect to the publisher: connection to server at \"host.docker.internal\" (192.168.65.2), port 5433 failed
```

You may need to adjust your docker networking or run Electric within docker. To run within Docker, you can build the docker image locally:

```sh
make docker-build
```

And then run with the right env vars, e.g.:

```sh
docker run -it -p "5433:5433" -p "5133:5133" \
    -e "ELECTRIC_HOST=host.docker.internal" \
    -e "CONNECTORS=pg1=postgresql://electric:password@host.docker.internal:54321/electric;pg2=postgresql://electric:password@host.docker.internal:54322/electric" \
    docker.io/library/electric:local-build
```

## Contributing

See the [Community Guidelines](https://github.com/electric-sql/meta) including the [Guide to Contributing](https://github.com/electric-sql/meta/blob/main/CONTRIBUTING.md) and [Contributor License Agreement](https://github.com/electric-sql/meta/blob/main/CLA.md).

## Support

We have an [open community Discord](https://discord.gg/B7kHGwDcbj). If you’re interested in the project, please come and say hello and let us know if you have any questions or need any help or support getting things running.
