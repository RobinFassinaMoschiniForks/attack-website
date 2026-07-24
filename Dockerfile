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
ARG VERSION_ARCHIVE_DIR="/var/cache/attack-website/version-archives"
ARG ATTACK_RELEASES_DIR="/var/cache/attack-website/attack-releases"
ARG DIFF_STIX_VERSION="v19.0"
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
    ATTACK_RELEASES_DIR=${ATTACK_RELEASES_DIR} \
    DIFF_STIX_VERSION=${DIFF_STIX_VERSION} \
    ATTACK_STIX_CACHE_DIR=/var/cache/attack-website/stix \
    STIX_LOCATION_ENTERPRISE=${STIX_LOCATION_ENTERPRISE} \
    STIX_LOCATION_MOBILE=${STIX_LOCATION_MOBILE} \
    STIX_LOCATION_ICS=${STIX_LOCATION_ICS} \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git \
    && curl -ksSL https://gitlab.mitre.org/mitre-scripts/mitre-pki/raw/master/os_scripts/install_certs.sh | sh \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/attack-website

COPY requirements.txt ./
RUN python3 -m pip install --no-cache-dir wheel \
    && python3 -m pip install --no-cache-dir -r requirements.txt

COPY . ./

# The generator copies theme assets into output/, so place the generated search bundle
# in the theme before running it. This mirrors the production GitLab pipeline.
COPY --from=search-build /src/attack-search/dist/search_bundle.js attack-theme/static/scripts/search_bundle.js

# Preserve the legacy STIX release input for the generated changelog. The BuildKit cache
# keeps these downloaded artifacts on the site host without adding them to the runtime image.
RUN --mount=type=cache,id=attack-website-artifacts-v1,target=/var/cache/attack-website,sharing=locked \
    download_attack_stix --download-dir "${ATTACK_RELEASES_DIR}" --all --stix21

# A Workbench API key is optional for local/upstream builds. When supplied as a BuildKit secret,
# it is available only to this command and is not persisted in an image layer.
RUN --mount=type=secret,id=workbench_api_key,required=false \
    --mount=type=cache,id=attack-website-artifacts-v1,target=/var/cache/attack-website,sharing=locked \
    if [ -f /run/secrets/workbench_api_key ]; then \
        export WORKBENCH_API_KEY="$(cat /run/secrets/workbench_api_key)"; \
        export WORKBENCH_USER; \
    fi; \
    mkdir -p "${VERSION_ARCHIVE_DIR}"; \
    python3 update-attack.py --attack-brand --extras ${UPDATE_ATTACK_EXTRAS} --no-test-exitstatus --version-archive-dir "${VERSION_ARCHIVE_DIR}"

# Preserve the non-SSH report phase from legacy CI: native website reports, STIX diff output,
# and the combined report. The data-quality reports that require Workbench SSH are omitted.
RUN --mount=type=secret,id=attack_update_scripts_token,required=true \
    --mount=type=cache,id=attack-website-artifacts-v1,target=/var/cache/attack-website,sharing=locked \
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
        --layers output/changes/layer-enterprise.json output/changes/layer-mobile.json output/changes/layer-ics.json \
    && git clone "https://gitlab-ci-token:$(cat /run/secrets/attack_update_scripts_token)@gitlab.mitre.org/attack-strategy/attack_update_scripts.git" /tmp/attack_update_scripts \
    && git -C /tmp/attack_update_scripts remote set-url origin https://gitlab.mitre.org/attack-strategy/attack_update_scripts.git \
    && python3 -m pip install --no-cache-dir -r /tmp/attack_update_scripts/requirements.txt \
    && python3 /tmp/attack_update_scripts/website-cicd/combine-test-reports.py --reports-dir output/reports/ --output-dir output/


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
