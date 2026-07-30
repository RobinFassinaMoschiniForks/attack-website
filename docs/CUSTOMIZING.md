# How to customize the ATT&CK Website

## Building the site with custom content

The MITRE ATT&CK Website® is designed to support an evolving knowledge base. The content seen on the site is generated from data in STIX JSON format.
Both STIX 2.0 and STIX 2.1 data is supported.
The data used to generate the live site at [attack.mitre.org](https://attack.mitre.org) can be found on our [mitre/cti](https://github.com/mitre/cti) github repo.

You can generate the website using custom content by replacing the STIX bundle locations in `modules/site_config.py`, `domains`.
A domain location can be a URL (please include http:// or https://), or a local file on disk.
Optionally, you can set the `STIX_LOCATION_ENTERPRISE`, `STIX_LOCATION_MOBILE`, `STIX_LOCATION_ICS`, or `STIX_LOCATION_PRE` environment variables to the URL or local file as well.

Matrices are defined in `modules/matrices/matrices_config.py`, you will need to update the structures declared in this file to modify the matrices.

## Configuration

### Changing the theme (colors)

Users wishing to make changes to the ATT&CK website visual theme should take a look at our scss source files in `attack-theme/static/style`.
Changes to the colors defined in `_colors.scss` should automatically propagate across the site.

### Changing logos

The logos used in the header, footer, and on the landing page of the website can be easily changed.
Simply find their keys in the `settings_dict` of `modules/website_build/website_build_config.py`, and update their values to point to the new images.

### Attaching a custom Navigator instance

Links to the [ATT&CK Navigator](https://github.com/mitre-attack/attack-navigator) can be customized to point to a custom instance of that application.
Simply change the `navigator_link` field in `modules/site_config.py` to point to your hosted instance, and all URLs pointing to the Navigator on the site should update automatically.

### Changing the banner

The banner message can be modified by changing the `BANNER_MESSAGE` property within `modules/site_config.py`.
You can also configure it through the Python build environment, as described below.

### Build environment variables

`update-attack.py` loads values from the shell environment and an optional `.env` file. Shell values take precedence over `.env` values. The variables below affect the Python site build. For Docker build arguments and examples, see the [Docker build guide](DOCKER.md).

Boolean values use case-insensitive parsing. `1`, `true`, `t`, `yes`, `y`, and `on` enable a setting; `0`, `false`, `f`, `no`, `n`, and `off` disable it. An unset or empty variable uses the documented default. When an equivalent command-line option is supplied, it takes precedence over the environment value.

#### Build behavior

| Variable | Default | Equivalent command-line option | Purpose |
| --- | --- | --- | --- |
| `ATTACK_BRAND` | `false` | `--attack-brand` / `--no-attack-brand` | Selects ATT&CK branding instead of the custom-instance theme. |
| `BANNER_ENABLED` | `true` | `--banner-enable` / `--banner-disable` | Shows or hides the site banner. |
| `BANNER_MESSAGE` | Custom-instance message | `--banner` | Supplies the HTML banner message. |
| `INCLUDE_OSANO` | `false` | `--include-osano` / `--no-include-osano` | Includes the Osano privacy compliance script. |
| `TEST_EXITSTATUS` | `true` | `--test-exitstatus` / `--no-test-exitstatus` | Controls whether site test failures produce a failing process status. |

An ATT&CK-branded build still hides the untouched stock custom-instance banner when the banner setting comes only from its default. Setting `BANNER_ENABLED` to a true value or passing `--banner-enable` explicitly shows it.

#### STIX data and archived versions

Each `STIX_LOCATION_*` value may be an HTTP(S) URL or a local JSON file path.

| Variable | Default | Purpose |
| --- | --- | --- |
| `STIX_LOCATION_ENTERPRISE` | MITRE CTI Enterprise ATT&CK JSON | STIX source for Enterprise ATT&CK content. |
| `STIX_LOCATION_MOBILE` | MITRE CTI Mobile ATT&CK JSON | STIX source for Mobile ATT&CK content. |
| `STIX_LOCATION_ICS` | MITRE CTI ICS ATT&CK JSON | STIX source for ICS ATT&CK content. |
| `STIX_LOCATION_PRE` | MITRE CTI PRE-ATT&CK JSON | STIX source for deprecated PRE-ATT&CK content. |
| `ATTACK_VERSION_ARCHIVES` | `attack-version-archives` | Directory used to cache and read archived site versions. |

#### External integrations

| Variable | Default | Equivalent command-line option | Purpose |
| --- | --- | --- | --- |
| `WORKBENCH_USER` | Unset | — | Workbench user name for authenticated STIX downloads. Used only with `WORKBENCH_API_KEY`. |
| `WORKBENCH_API_KEY` | Unset | — | Workbench API key for authenticated STIX downloads. Used only with `WORKBENCH_USER`; keep it out of version control. |
| `GOOGLE_ANALYTICS` | Unset | `--google-analytics` | Google Analytics identifier included in generated pages. |
| `GOOGLE_SITE_VERIFICATION` | Unset | `--google-site-verification` | Google site-verification value included in generated pages. |

#### Pelican metadata

| Variable | Default | Purpose |
| --- | --- | --- |
| `PELICAN_AUTHOR` | `MITRE` | Author metadata supplied to Pelican. |
| `PELICAN_SITENAME` | `ATT&CK` | Site-name metadata supplied to Pelican. |
| `PELICAN_SITEURL` | Empty string | Canonical site URL used by Pelican. |
| `PELICAN_TIMEZONE` | `America/New_York` | Time zone supplied to Pelican. |
| `PELICAN_DEFAULT_LANG` | `en` | Default language supplied to Pelican. |

For example, use the ATT&CK theme and include Osano when building locally:

```shell
ATTACK_BRAND=true INCLUDE_OSANO=true python3 update-attack.py
```

## Implementation Overview

The ATT&CK Website uses a combination of Python, Pelican and Jinja to convert the STIX content into a set of static HTML files.
When `update-attack.py` is run, it generates a set of markdown files in `content` containing the parsed STIX content.
Pelican then reads these markdown files and uses them with the Jinja templates in `attack-theme/templates` to build the site HTML in the output directory.

## Adding New Features

The website is built from modules.
These modules can be found inside the `modules` directory.
If the `update-attack.py` script is ran without any arguments, it will automatically look for modules inside the `modules` directory and build them.
Modules are divided in two classes, active and supportive modules.
Active modules append a link to the website's main menu and typically generates markdown files.
For example, the `techniques` module is responsible for generating all Technique related markdown pages.
Supportive modules are those who do not appear on the website menu but are critical to the general website build.
An example of a supportive module is the `util` module which has methods and API calls to interface with the STIX bundles.

Modules that are not present on the `modules` directory will not get built and will not appear on the website's main navigation menu.
You can also select specific modules to be run without removing modules from the directory by repeating the `-m` option for each selected module.
For example, run `python3 update-attack.py -m clean -m techniques -m website_build` to run a fresh build, generate the techniques markdown files, and generate the HTML files.
Supportive modules need not to be called by arguments flags unless they are optional supportive modules such as the `tests` module.
Select individual extra modules by repeating `--extras` (for example, `--extras resources --extras blog`), or use `--all-extras` to select every extra module.
The `--all-extras` and `--extras` options cannot be combined.

The options accept one value each. Commands written for versions before 5.0.0 that place several values after one option must be updated:

| Before v5.0.0 | v5.0.0 and later |
| --- | --- |
| `-m clean techniques website_build` | `-m clean -m techniques -m website_build` |
| `-t size links citations` | `-t size -t links -t citations` |
| `-e resources blog` | `-e resources -e blog` |
| `--extras` | `--all-extras` |

### Building your own module

To build your own module, create a folder inside of the `modules` directory with the name of the module.
Typically, a module will have three files: `__init__py`, `your_module-s_name.py`, `your_module-s_name_config.py`.
The `__init__.py` file contains methods that are used to determine the run priority or if they will appear on website’s main menu.
For example, if it is an active module that will appear on the website's menu, be sure to include `get_menu()`, `get_priority()`, and `run_module()` in the `__init__.py` file (see the following code snippet for an example).
The module can be added to the website's menu as a single link to the main module page and/or can include links to subpages in a hoverable dropdown menu.
If the module is an active or an optional supportive one, add the name to the argument list (`module_choices`), found in the `update-attack.py` script.

```python
from . import your_module-s_name
from . import your_module-s_name_config

def get_priority():
    return your_module-s_name_config.priority

def get_menu():
    return {
        "display_name": "Name that will be displayed in the navigation menu"
        "module_name": "Your module's name",
        "url": "/your_module-s_name/",
        "external_link": False,
        "priority": your_module-s_name_config.priority,
        "children": [
            {
                "display_name": "Module sub-menu page",
                "url": "/your_module-s_name/subpage",
                "external_link": False,
                "children": []
            },
            ...
            {
                "display_name": "Module sub-menu external page",
                "url": "https://attack.mitre.org",
                "external_link": True,
                "children": []
            }
        ]
    }

def run_module():
    return (your_module-s_name.generate_your_module-s_name(), your_module-s_name_config.module_name)
```

Every module has a given priority number.
This number is used to determine the order on which the modules are ran.
The build script will run the modules in an ascending priority order (lowest priority number will run first).
The priority inside of the `get_menu()` will determine the website's main menu order from left to right; module with the lowest priority number will be on the left.

`your_module-s_name_config.py` typically contains variables or string templates that are shared throughout the module.
`your_module-s_name.py` contains the methods that generate markdown files or are used to help other modules.

Jinja templates that are only used by the module should be stored in the module under a folder named `templates`, and then moved to the general templates folder.
This will help reduce the clutter of unused templates.

Additionally, redirections made by the module should also be stored inside of the module.
Take a look at the available modules for reference (the techniques module is a good one).
