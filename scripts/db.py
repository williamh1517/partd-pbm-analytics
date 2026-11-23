"""Shared Postgres connection settings. Override with PG* environment variables."""

import os

import psycopg2
from sqlalchemy import create_engine

PG = {
    "host": os.getenv("PGHOST", "localhost"),
    "port": int(os.getenv("PGPORT", "5433")),
    "dbname": os.getenv("PGDATABASE", "partd"),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD", "postgres"),
}


def connect():
    return psycopg2.connect(**PG)


def engine():
    host = PG["host"]
    # A host starting with "/" is a Unix socket directory.
    if host.startswith("/"):
        url = f"postgresql+psycopg2://{PG['user']}@/{PG['dbname']}?host={host}&port={PG['port']}"
    else:
        url = (
            f"postgresql+psycopg2://{PG['user']}:{PG['password']}"
            f"@{host}:{PG['port']}/{PG['dbname']}"
        )
    return create_engine(url)
