# Docker build guide

The root `Dockerfile` builds the search bundle, generates the static website, and serves the resulting site with Nginx. It uses Node.js 26 (`node:26-bookworm-slim`), Python 3.13 (`python:3.13-slim-bookworm`), and `nginx:stable-alpine`.

## Build and run

Build the production image from the repository root:

```shell
docker build -t attack-website .
docker run --rm -p 80:80 attack-website
```

The website is then available at <http://localhost>.

## Build arguments

Use `--build-arg NAME=value` to customize a build. `ATTACK_BRAND`, `BANNER_ENABLED`, `INCLUDE_OSANO`, `TEST_EXITSTATUS`, and `UPDATE_ATTACK_ALL_EXTRAS` are passed to Typer and accept its Boolean values: `1`, `true`, `t`, `yes`, `y`, and `on` enable a setting; `0`, `false`, `f`, `no`, `n`, and `off` disable it. The Docker-only `GENERATE_STIX_CHANGELOG` argument requires the exact lowercase value `true` to enable it; every other value disables it.

| Argument | Default | Purpose |
| --- | --- | --- |
| `ATTACK_BRAND` | `false` | Use the ATT&CK-branded theme. |
| `BANNER_ENABLED` | CLI default (`true`) | Show the site banner. |
| `BANNER_MESSAGE` | Custom-instance message | Set the banner content. |
| `INCLUDE_OSANO` | `false` | Include the Osano privacy script. |
| `TEST_EXITSTATUS` | `true` | Preserve a nonzero exit status when site tests fail. |
| `UPDATE_ATTACK_ALL_EXTRAS` | `false` | Run every optional extra module. |
| `UPDATE_ATTACK_EXTRAS` | Empty | Space-separated optional extra modules, such as `resources blog`. |
| `STIX_LOCATION_ENTERPRISE` | MITRE CTI Enterprise bundle | Override the Enterprise STIX source. |
| `STIX_LOCATION_MOBILE` | MITRE CTI Mobile bundle | Override the Mobile STIX source. |
| `STIX_LOCATION_ICS` | MITRE CTI ICS bundle | Override the ICS STIX source. |
| `STIX_LOCATION_PRE` | MITRE CTI PRE bundle | Override the PRE-ATT&CK STIX source. |
| `PELICAN_SITEURL` | Empty | Set Pelican's canonical site URL. |
| `GOOGLE_ANALYTICS` | Empty | Set the Google Analytics identifier. |
| `GOOGLE_SITE_VERIFICATION` | Empty | Set the Google site-verification value. |
| `GENERATE_STIX_CHANGELOG` | `false` | Generate a STIX changelog in the image. |
| `VERSION_ARCHIVE_DIR` | `/var/cache/attack-website/version-archives` | Archive cache location. |
| `ATTACK_RELEASES_DIR` | `/var/cache/attack-website/attack-releases` | Downloaded release cache location. |
| `DIFF_STIX_VERSION` | `v19.1` | Prior ATT&CK version used for changelog generation. |

`UPDATE_ATTACK_ALL_EXTRAS` and `UPDATE_ATTACK_EXTRAS` are mutually exclusive, just like `--all-extras` and `--extras` in `update-attack.py`.

For example, build an ATT&CK-branded image with all optional extras:

```shell
docker build \
  --build-arg ATTACK_BRAND=true \
  --build-arg UPDATE_ATTACK_ALL_EXTRAS=true \
  -t attack-website .
```

## Test exit behavior

The Docker build does not add `--no-test-exitstatus`. Instead, it exports `TEST_EXITSTATUS` to `update-attack.py`, whose Typer option reads that environment variable. The default (`true`) makes the Docker build fail when the site tests fail. To retain the generated site and treat site-test failures as warnings, set it to `false`:

```shell
docker build --build-arg TEST_EXITSTATUS=false -t attack-website .
```

This setting affects site-test failures only. Other `update-attack.py` failures still stop the Docker build.

## Workbench credentials and trust setup

Pass the Workbench API key through a BuildKit secret; do not put it in a build argument or image environment variable. Supply `WORKBENCH_USER` as a build argument when using the secret:

```shell
docker build \
  --build-arg WORKBENCH_USER=example-user \
  --secret id=workbench_api_key,src=/path/to/workbench-api-key \
  -t attack-website .
```

The Dockerfile also supports `OS_CA_TRUST_SETUP_COMMAND` and `PYTHON_CA_TRUST_SETUP_COMMAND` for environments that require additional certificate trust configuration. Both default to the POSIX no-op command (`:`).
