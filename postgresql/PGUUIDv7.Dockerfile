FROM focker.ir/postgres:latest
WORKDIR /pg_uuidv7
RUN apt -qq update && apt -qqy install curl
RUN curl -LsO "https://github.com/fboulnois/pg_uuidv7/releases/download/v1.6.0/{pg_uuidv7.tar.gz,SHA256SUMS}"
RUN tar -xvzf pg_uuidv7.tar.gz --wildcards "${PG_MAJOR}/*" 'pg_uuidv7--1.6.sql' 'pg_uuidv7.control' && cat SHA256SUMS | grep -e "${PG_MAJOR}/pg_uuidv7.so" -e "pg_uuidv7--1.6.sql" -e "pg_uuidv7.control" | sha256sum -c --quiet
RUN cp ${PG_MAJOR}/pg_uuidv7.so $(pg_config --pkglibdir) && cp pg_uuidv7--1.6.sql pg_uuidv7.control "$(pg_config --sharedir)/extension"
RUN echo 'CREATE EXTENSION pg_uuidv7;' > /docker-entrypoint-initdb.d/create-uuidv7-ext.sql
WORKDIR /
