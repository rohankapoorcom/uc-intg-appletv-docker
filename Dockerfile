# Docker image for the Unfolded Circle Apple TV integration.
#
# This Dockerfile is applied to a checkout of the upstream source
# (unfoldedcircle/integration-appletv) at a tagged release. The build context is
# the upstream tree, not this repo.
#
# Multi-stage: the builder stage uses the full python image (which ships a C/C++
# toolchain) so native dependencies without prebuilt wheels (e.g. miniaudio on
# linux/arm64) can compile. The runtime stage stays on the slim image with no
# compiler.
#
# driver_id handling (HASS pattern): the upstream driver.json is shipped
# UNCHANGED (driver_id: appletv). External deployments register a distinct
# driver_id (e.g. appletv_external) on the Remote via the Core-API and disable
# mDNS (UC_DISABLE_MDNS_PUBLISH=true), pointing the Remote at a fixed wss:// URL.

FROM python:3.11-bullseye AS builder

WORKDIR /app
COPY requirements.txt .
# Install into a relocatable prefix that is copied into the runtime stage.
RUN pip3 install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim-bullseye

WORKDIR /app

# gettext provides msgfmt and make drives the locale Makefile (.po -> .mo)
RUN apt-get update \
    && apt-get install -y --no-install-recommends gettext make \
    && rm -rf /var/lib/apt/lists/*

# Python dependencies built in the builder stage (matches /usr/local layout).
COPY --from=builder /install /usr/local

ARG CONFIG_PATH=/config
ENV UC_CONFIG_HOME=$CONFIG_PATH
RUN mkdir -p "$CONFIG_PATH" && chown 10000 "$CONFIG_PATH"

COPY . .

# Compile gettext translations. driver.json is intentionally left untouched.
RUN cd intg-appletv/locales && make all

ENV UC_INTEGRATION_INTERFACE=0.0.0.0
ENV UC_INTEGRATION_HTTP_PORT=9090

# Run as non-root; the config dir above is owned by this uid.
USER 10000
VOLUME $CONFIG_PATH

CMD ["python3", "-u", "intg-appletv/driver.py"]
