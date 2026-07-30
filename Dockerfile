# syntax=docker/dockerfile:1.7

FROM node:26-bookworm-slim AS search-build

WORKDIR /src/attack-search

COPY attack-search/package*.json ./
RUN npm ci

COPY attack-search/webpack.config.cjs ./
COPY attack-search/src ./src
RUN npm run build


FROM python:3.13-slim-bookworm AS site-base

ARG PELICAN_SITEURL=""
ARG BANNER_ENABLED="true"
ARG BANNER_MESSAGE=""
ARG INCLUDE_OSANO="false"
ARG GOOGLE_ANALYTICS=""
ARG GOOGLE_SITE_VERIFICATION=""
ARG ATTACK_BRAND="false"
ARG TEST_EXITSTATUS="true"
ARG UPDATE_ATTACK_EXTRAS=""
ARG UPDATE_ATTACK_ALL_EXTRAS="false"
ARG GENERATE_STIX_CHANGELOG="false"
ARG VERSION_ARCHIVE_DIR="/var/cache/attack-website/version-archives"
ARG ATTACK_RELEASES_DIR="/var/cache/attack-website/attack-releases"
ARG DIFF_STIX_VERSION="v19.1"
ARG STIX_LOCATION_ENTERPRISE="https://raw.githubusercontent.com/mitre/cti/master/enterprise-attack/enterprise-attack.json"
ARG STIX_LOCATION_MOBILE="https://raw.githubusercontent.com/mitre/cti/master/mobile-attack/mobile-attack.json"
ARG STIX_LOCATION_ICS="https://raw.githubusercontent.com/mitre/cti/master/ics-attack/ics-attack.json"
ARG STIX_LOCATION_PRE="https://raw.githubusercontent.com/mitre/cti/master/pre-attack/pre-attack.json"
ARG WORKBENCH_USER=""
# `:` is the POSIX shell no-op, used when optional setup commands are not supplied.
ARG OS_CA_TRUST_SETUP_COMMAND=":"
ARG PYTHON_CA_TRUST_SETUP_COMMAND=":"

ENV PELICAN_SITEURL=${PELICAN_SITEURL} \
    BANNER_ENABLED=${BANNER_ENABLED} \
    BANNER_MESSAGE=${BANNER_MESSAGE} \
    GOOGLE_ANALYTICS=${GOOGLE_ANALYTICS} \
    GOOGLE_SITE_VERIFICATION=${GOOGLE_SITE_VERIFICATION} \
    ATTACK_BRAND=${ATTACK_BRAND} \
    INCLUDE_OSANO=${INCLUDE_OSANO} \
    TEST_EXITSTATUS=${TEST_EXITSTATUS} \
    UPDATE_ATTACK_EXTRAS=${UPDATE_ATTACK_EXTRAS} \
    UPDATE_ATTACK_ALL_EXTRAS=${UPDATE_ATTACK_ALL_EXTRAS} \
    VERSION_ARCHIVE_DIR=${VERSION_ARCHIVE_DIR} \
    ATTACK_RELEASES_DIR=${ATTACK_RELEASES_DIR} \
    DIFF_STIX_VERSION=${DIFF_STIX_VERSION} \
    STIX_LOCATION_ENTERPRISE=${STIX_LOCATION_ENTERPRISE} \
    STIX_LOCATION_MOBILE=${STIX_LOCATION_MOBILE} \
    STIX_LOCATION_ICS=${STIX_LOCATION_ICS} \
    STIX_LOCATION_PRE=${STIX_LOCATION_PRE} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git \
    && sh -ec "${OS_CA_TRUST_SETUP_COMMAND}" \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/attack-website

COPY requirements.txt ./
RUN python3 -m pip install --no-cache-dir wheel \
    && python3 -m pip install --no-cache-dir -r requirements.txt \
    && sh -ec "${PYTHON_CA_TRUST_SETUP_COMMAND}"

COPY . ./

# The generator copies theme assets into output/, so place the generated search bundle
# in the theme before running it.
COPY --from=search-build /src/attack-search/dist/search_bundle.js attack-theme/static/scripts/search_bundle.js


FROM site-base AS website-build

# A Workbench API key is optional for local/upstream builds. When supplied as a BuildKit secret,
# it is available only to this command and is not persisted in an image layer.
RUN --mount=type=secret,id=workbench_api_key,required=false \
    --mount=type=cache,id=attack-website-artifacts-v1,target=/var/cache/attack-website,sharing=locked \
    if [ -f /run/secrets/workbench_api_key ]; then \
        export WORKBENCH_API_KEY="$(cat /run/secrets/workbench_api_key)"; \
        export WORKBENCH_USER; \
    fi; \
    mkdir -p "${VERSION_ARCHIVE_DIR}"; \
    set --; \
    if [ -n "${UPDATE_ATTACK_EXTRAS}" ]; then \
        set -f; \
        for extra in ${UPDATE_ATTACK_EXTRAS}; do \
            set -- "$@" --extras "$extra"; \
        done; \
    fi; \
    python3 update-attack.py "$@" \
        --version-archive-dir "${VERSION_ARCHIVE_DIR}"


FROM website-build AS changelog-build

RUN --mount=type=cache,id=attack-website-artifacts-v1,target=/var/cache/attack-website,sharing=locked \
    if [ "${GENERATE_STIX_CHANGELOG}" = "true" ]; then \
        download_attack_stix --download-dir "${ATTACK_RELEASES_DIR}" --all --stix21; \
    fi

RUN --mount=type=cache,id=attack-website-artifacts-v1,target=/var/cache/attack-website,sharing=locked \
    if [ "${GENERATE_STIX_CHANGELOG}" = "true" ]; then \
        mkdir -p output/reports output/changes \
        && cp reports/* output/reports/ \
        && cp reports/tests.html output/ \
        && diff_stix -v \
            --old "${ATTACK_RELEASES_DIR}/stix-2.0/${DIFF_STIX_VERSION}/" \
            --new output/stix/ \
            --show-key \
            --contributors \
            --html-file output/changes/index.html \
            --html-file-detailed output/changes/changelog-detailed.html \
            --markdown-file output/changes/changelog.md \
            --json-file output/changes/changelog.json \
            --layers output/changes/layer-enterprise.json output/changes/layer-mobile.json output/changes/layer-ics.json; \
    fi


FROM nginx:stable-alpine AS production

COPY --from=changelog-build /src/attack-website/output /var/www/html
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
