ARG NODE_VERSION=12
ARG PYTHON_VERSION=3.8

#
# --- Build assets with NodeJS
#

FROM node:$NODE_VERSION AS build

# Superset version to build
ARG SUPERSET_VERSION=1.5.0
ENV SUPERSET_HOME=/var/lib/superset

# Download source
WORKDIR $SUPERSET_HOME
RUN wget -qO /tmp/superset.tar.gz https://github.com/apache/superset/archive/$SUPERSET_VERSION.tar.gz
RUN tar xzf /tmp/superset.tar.gz -C $SUPERSET_HOME --strip-components=1

# Build assets
WORKDIR $SUPERSET_HOME/superset-frontend/
RUN npm install 2> /dev/null
RUN npm run build 2> /dev/null

#
# --- Build dist package with Python 3
#

FROM python:$PYTHON_VERSION AS dist

# Copy prebuilt workspace into stage
ENV SUPERSET_HOME=/var/lib/superset
WORKDIR $SUPERSET_HOME
COPY --from=build $SUPERSET_HOME .
COPY requirements.txt .

# Create package to install
RUN python setup.py sdist
RUN tar czfv /tmp/superset.tar.gz requirements.txt dist

#
# --- Install dist package and finalize app
#

FROM python:$PYTHON_VERSION AS final

# Configure environment
# superset recommended defaults: https://superset.apache.org/docs/installation/configuring-superset#running-on-a-wsgi-http-server
# gunicorn recommended defaults: https://docs.gunicorn.org/en/0.17.2/configure.html#security
ENV GUNICORN_BIND=0.0.0.0:8088
ENV GUNICORN_LIMIT_REQUEST_FIELD_SIZE=8190
ENV GUNICORN_LIMIT_REQUEST_LINE=8190
ENV GUNICORN_THREADS=4
ENV GUNICORN_TIMEOUT=120
ENV GUNICORN_WORKERS=10
ENV GUNICORN_WORKER_CLASS=gevent
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PYTHONPATH=/etc/superset:/home/superset:$PYTHONPATH
ENV SUPERSET_REPO=apache/superset
ENV SUPERSET_VERSION=$SUPERSET_VERSION
ENV SUPERSET_HOME=/var/lib/superset
ENV GUNICORN_CMD_ARGS="--bind $GUNICORN_BIND --limit-request-field_size $GUNICORN_LIMIT_REQUEST_FIELD_SIZE --limit-request-line $GUNICORN_LIMIT_REQUEST_LINE --threads $GUNICORN_THREADS --timeout $GUNICORN_TIMEOUT --workers $GUNICORN_WORKERS --worker-class $GUNICORN_WORKER_CLASS"

# Create superset user & install dependencies
WORKDIR /tmp/superset
COPY --from=dist /tmp/superset.tar.gz .
RUN groupadd supergroup && \
    useradd -U -m -G supergroup superset && \
    mkdir -p /etc/superset && \
    mkdir -p $SUPERSET_HOME && \
    chown -R superset:superset /etc/superset && \
    chown -R superset:superset $SUPERSET_HOME && \
    apt-get update && \
    apt-get install -y \
        build-essential \
        curl \
        default-libmysqlclient-dev \
        freetds-bin \
        freetds-dev \
        libaio1 \
        libffi-dev \
        libldap2-dev \
        libpq-dev \
        libsasl2-2 \
        libsasl2-dev \
        libsasl2-modules-gssapi-mit \
        libssl-dev && \
    apt-get clean && \
    tar xzf superset.tar.gz && \
    pip install Cython==0.29.23 pystan==2.19.1.1 && \
    pip install dist/*.tar.gz -r requirements.txt && \
    rm -rf /tmp/superset

# Configure Filesystem
COPY bin /usr/local/bin
WORKDIR /home/superset
VOLUME /etc/superset
VOLUME /home/superset
VOLUME /var/lib/superset

# Finalize application
EXPOSE 8088
HEALTHCHECK CMD ["curl", "-f", "http://localhost:8088/health"]
CMD ["gunicorn", "superset.app:create_app()"]
USER superset
