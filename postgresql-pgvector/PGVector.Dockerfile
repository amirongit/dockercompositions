FROM focker.ir/postgres:latest
RUN apt -qq update && apt -qqy install git make gcc postgresql-server-dev-18
RUN git clone --quiet --branch v0.8.7 https://github.com/pgvector/pgvector.git /pgvector
WORKDIR /pgvector
RUN make && make install
RUN echo 'CREATE EXTENSION vector;' > /docker-entrypoint-initdb.d/setup-vector-ext.sql
WORKDIR /
