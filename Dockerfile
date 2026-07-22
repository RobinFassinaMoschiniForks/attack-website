# syntax=docker/dockerfile:1.7

FROM node:18-bookworm-slim AS search-build

WORKDIR /src/attack-search

COPY attack-search/package*.json ./
RUN npm ci

COPY attack-search/webpack.config.cjs ./
COPY attack-search/src ./src
RUN npm run build


FROM python:3.13-slim-bookworm AS site-build

ARG PELICAN_SITEURL=""
ARG BANNER_ENABLED="true"
ARG BANNER_MESSAGE=""
ARG INCLUDE_OSANO="false"
ARG GOOGLE_ANALYTICS=""
ARG GOOGLE_SITE_VERIFICATION=""
ARG UPDATE_ATTACK_EXTRAS="resources blog stixtests benefactors versions"
ARG VERSION_ARCHIVE_DIR="/opt/attack-version-archives"
ARG STIX_LOCATION_ENTERPRISE="https://raw.githubusercontent.com/mitre/cti/master/enterprise-attack/enterprise-attack.json"
ARG STIX_LOCATION_MOBILE="https://raw.githubusercontent.com/mitre/cti/master/mobile-attack/mobile-attack.json"
ARG STIX_LOCATION_ICS="https://raw.githubusercontent.com/mitre/cti/master/ics-attack/ics-attack.json"
ARG WORKBENCH_USER=""

ENV PELICAN_SITEURL=${PELICAN_SITEURL} \
    BANNER_ENABLED=${BANNER_ENABLED} \
    BANNER_MESSAGE=${BANNER_MESSAGE} \
    INCLUDE_OSANO=${INCLUDE_OSANO} \
    GOOGLE_ANALYTICS=${GOOGLE_ANALYTICS} \
    GOOGLE_SITE_VERIFICATION=${GOOGLE_SITE_VERIFICATION} \
    UPDATE_ATTACK_EXTRAS=${UPDATE_ATTACK_EXTRAS} \
    VERSION_ARCHIVE_DIR=${VERSION_ARCHIVE_DIR} \
    STIX_LOCATION_ENTERPRISE=${STIX_LOCATION_ENTERPRISE} \
    STIX_LOCATION_MOBILE=${STIX_LOCATION_MOBILE} \
    STIX_LOCATION_ICS=${STIX_LOCATION_ICS} \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/attack-website

COPY requirements.txt ./
RUN python3 -m pip install --no-cache-dir wheel \
    && python3 -m pip install --no-cache-dir -r requirements.txt

COPY . ./

# The generator copies theme assets into output/, so place the generated search bundle
# in the theme before running it. This mirrors the production GitLab pipeline.
COPY --from=search-build /src/attack-search/dist/search_bundle.js attack-theme/static/scripts/search_bundle.js

# A Workbench API key and internal CA are optional for local/upstream builds. When supplied
# as BuildKit secrets, they are available only to this command and are not persisted in an image layer.
RUN --mount=type=secret,id=workbench_api_key,required=false \
    --mount=type=secret,id=internal_ca,target=/usr/local/share/ca-certificates/internal-ca.crt,required=false \
    if [ -f /usr/local/share/ca-certificates/internal-ca.crt ]; then \
        update-ca-certificates; \
    fi; \
    if [ -f /run/secrets/workbench_api_key ]; then \
        export WORKBENCH_API_KEY="$(cat /run/secrets/workbench_api_key)"; \
        export WORKBENCH_USER; \
    fi; \
    mkdir -p "${VERSION_ARCHIVE_DIR}"; \
    python3 update-attack.py --attack-brand --extras ${UPDATE_ATTACK_EXTRAS} --no-test-exitstatus --version-archive-dir "${VERSION_ARCHIVE_DIR}"


FROM nginx:stable-alpine AS production

COPY --from=site-build /src/attack-website/output /var/www/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

LABEL org.opencontainers.image.title="ATT&CK Website" \
    org.opencontainers.image.description="Static ATT&CK Website served by Nginx" \
    org.opencontainers.image.source="https://github.com/mitre-attack/attack-website" \
    org.opencontainers.image.url="https://attack.mitre.org/" \
    org.opencontainers.image.vendor="MITRE ATT&CK"

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
