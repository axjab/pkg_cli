FROM debian:trixie-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl sudo \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash pkgtest \
    && printf '%s\n' 'pkgtest ALL=(root) NOPASSWD: ALL' > /etc/sudoers.d/pkgtest \
    && chmod 0440 /etc/sudoers.d/pkgtest \
    && visudo -c

USER pkgtest
WORKDIR /home/pkgtest
CMD ["bash"]
