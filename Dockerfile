FROM alpine:3.20 AS builder

ARG IMAPFILTER_REPO=https://github.com/lefcha/imapfilter.git
ARG IMAPFILTER_REF=master
ARG IMAPFILTER_COMMIT=

RUN apk add --no-cache \
    git \
    lua-dev \
    gcc \
    make \
    openssl-dev \
    pcre2-dev \
    g++ \
    ca-certificates

WORKDIR /src
RUN git clone --depth 1 --branch "${IMAPFILTER_REF}" "${IMAPFILTER_REPO}" imapfilter
RUN if [ -n "${IMAPFILTER_COMMIT}" ]; then \
      git -C imapfilter fetch --depth 1 origin "${IMAPFILTER_COMMIT}" \
      && git -C imapfilter checkout --detach "${IMAPFILTER_COMMIT}"; \
    fi

WORKDIR /src/imapfilter
RUN make all && make install

FROM alpine:3.20
ARG IMAPFILTER_REPO=https://github.com/lefcha/imapfilter.git
ARG IMAPFILTER_REF=master
ARG IMAPFILTER_COMMIT=

LABEL org.opencontainers.image.title="docker-imapfilter"
LABEL org.opencontainers.image.description="Container image for running imapfilter"
LABEL org.opencontainers.image.authors="unclesamwk"
LABEL org.opencontainers.image.source="${IMAPFILTER_REPO}"
LABEL org.opencontainers.image.version="${IMAPFILTER_REF}"

RUN apk add --no-cache \
    bash \
    lua5.1-libs \
    openssl \
    pcre2 \
    libstdc++ \
    ca-certificates \
    tzdata \
    tini

ENV TZ=Europe/Berlin
ENV HOME=/home/imap
ENV IMAPFILTER_CONFIG=/home/imap/.imapfilter/config.lua
ENV IMAPFILTER_INTERVAL_SECONDS=60
ENV IMAPFILTER_ONCE=false
ENV IMAPFILTER_EXTRA_ARGS=
ENV IMAPFILTER_FAILURE_BACKOFF_SECONDS=15
ENV IMAPFILTER_MAX_BACKOFF_SECONDS=300
ENV IMAPFILTER_HEARTBEAT_FILE=/tmp/imapfilter.last_success_epoch
ENV IMAPFILTER_HEALTH_MAX_AGE_SECONDS=0

RUN ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime \
    && echo "${TZ}" > /etc/timezone \
    && addgroup -S imap \
    && adduser -S -G imap -h /home/imap imap \
    && mkdir -p /home/imap/.imapfilter \
    && chown -R imap:imap /home/imap

COPY --from=builder /usr/local/bin/imapfilter /usr/local/bin/imapfilter
COPY --from=builder /usr/local/share/imapfilter /usr/local/share/imapfilter
COPY run.sh /usr/local/bin/run.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod +x /usr/local/bin/run.sh /usr/local/bin/healthcheck.sh

USER imap
WORKDIR /home/imap
HEALTHCHECK --interval=60s --timeout=5s --start-period=60s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/run.sh"]
