import time
from enum import Enum
from types import SimpleNamespace
from typing import Annotated

import typer
from dotenv import load_dotenv
from loguru import logger

import modules
from modules import site_config

load_dotenv()

# argument defaults and options for the CLI
module_choices = [
    "clean",
    # NOTE: While datasources are deprecated starting in ATT&CK v18, we still include them for legacy support.
    # All Datasource objects should be individually deprecated, but still have pages generated.
    "datasources",
    "groups",
    "search",
    "matrices",
    "mitigations",
    "software",
    "tactics",
    "techniques",
    "campaigns",
    "assets",
    "datacomponents",
    "detectionstrategies",
    "analytics",
    "tour",
    "website_build",
    "random_page",
    "redirections",
    "subdirectory",
    "tests",
]
extras = ["resources", "versions", "blog", "stixtests", "benefactors", "contribute"]
test_choices = ["size", "links", "external_links", "citations"]

ModuleChoice = Enum("ModuleChoice", {choice.upper(): choice for choice in module_choices}, type=str)
ExtraChoice = Enum("ExtraChoice", {choice.upper(): choice for choice in extras}, type=str)
TestChoice = Enum("TestChoice", {choice.upper(): choice for choice in test_choices}, type=str)

DESCRIPTION = (
    "Build the ATT&CK website.\n"
    "All flags are optional. If you run the build without flags, "
    "the modules that pertain to the ATT&CK dataset will be ran. "
    "If you would like to run extra modules, opt-in these modules with the "
    "--extras or --all-extras flag."
)


app = typer.Typer(
    add_completion=False,
    context_settings={"help_option_names": ["-h", "--help"]},
    pretty_exceptions_enable=False,
)


def validate_subdirectory_string(subdirectory_str: str | None) -> str | None:
    """Validate subdirectory string."""
    if subdirectory_str is None:
        return None

    if not subdirectory_str.isascii():
        raise typer.BadParameter(f"{subdirectory_str} contains non ascii characters")

    # Remove leading and trailing /
    if subdirectory_str.startswith("/"):
        subdirectory_str = subdirectory_str[1:]
    if subdirectory_str.endswith("/"):
        subdirectory_str = subdirectory_str[:-1]

    site_config.set_subdirectory(subdirectory_str)

    return subdirectory_str


@app.command(help=DESCRIPTION)
def cli(
    ctx: typer.Context,
    no_stix_link_replacement: Annotated[
        bool,
        typer.Option(
            "--no-stix-link-replacement",
            help=(
                "If this flag is absent, links to attack.mitre.org/[page] in the STIX data will be replaced "
                "with /[page]. Add this flag to preserve links to attack.mitre.org."
            ),
        ),
    ] = False,
    modules_to_run: Annotated[
        list[ModuleChoice] | None,
        typer.Option(
            "--modules",
            "-m",
            help=(
                "Run a specific module. Repeat the option to select multiple modules, for example: "
                "'-m clean -m techniques -m tactics'. Runs all modules when the option is not used."
            ),
        ),
    ] = None,
    extra_modules: Annotated[
        list[ExtraChoice] | None,
        typer.Option(
            "--extras",
            "-e",
            help=(
                "Run an extra module that does not pertain to the ATT&CK dataset. Repeat the option to select "
                "multiple extras, for example: '-e resources -e blog'. Use --all-extras to run every extra module."
            ),
        ),
    ] = None,
    all_extras: Annotated[
        bool,
        typer.Option(
            "--all-extras",
            envvar="ATTACK_WEBSITE_UPDATE_ATTACK_ALL_EXTRAS",
            show_envvar=True,
            help="Run every extra module. Cannot be combined with --extras.",
        ),
    ] = False,
    selected_tests: Annotated[
        list[TestChoice] | None,
        typer.Option(
            "--test",
            "-t",
            help=(
                "Run a specific test. Repeat the option to select multiple tests. Tests: size (output size against "
                "the GitHub Pages limit); links (dead internal and relative links); external_links (dead external "
                "links); citations (unparsed citation text)."
            ),
        ),
    ] = None,
    attack_brand: Annotated[
        bool,
        typer.Option(
            "--attack-brand/--no-attack-brand",
            envvar="ATTACK_WEBSITE_ATTACK_BRAND",
            show_envvar=True,
            help="Apply ATT&CK brand colors; false uses custom-instance styling.",
        ),
    ] = False,
    proxy: Annotated[str | None, typer.Option("--proxy", help="Set proxy.")] = None,
    subdirectory: Annotated[
        str | None,
        typer.Option(
            "--subdirectory",
            callback=validate_subdirectory_string,
            help="Host the site from the specified subdirectory.",
        ),
    ] = None,
    print_tests: Annotated[
        bool,
        typer.Option("--print-tests", help="Print test output to stdout even if the results are very long."),
    ] = False,
    test_exitstatus: Annotated[
        bool,
        typer.Option(
            "--test-exitstatus/--no-test-exitstatus",
            envvar="ATTACK_WEBSITE_TEST_EXITSTATUS",
            show_envvar=True,
            help="Preserve failing site-test exit codes; disable to force a successful process status.",
        ),
    ] = True,
    version_archive_dir: Annotated[
        str | None,
        typer.Option(
            "--version-archive-dir",
            help="Set the ATT&CK version archive directory. Defaults to attack-version-archives.",
        ),
    ] = None,
    banner: Annotated[
        str | None,
        typer.Option(
            "--banner",
            help=(
                "Set the site banner text. Otherwise use modules/site_config.py BANNER_MESSAGE or the "
                "ATTACK_WEBSITE_BANNER_MESSAGE environment variable."
            ),
        ),
    ] = None,
    banner_enabled: Annotated[
        bool,
        typer.Option(
            "--banner-enable/--banner-disable",
            envvar="ATTACK_WEBSITE_BANNER_ENABLED",
            show_envvar=True,
            help="Enable or disable the site banner.",
        ),
    ] = True,
    google_analytics: Annotated[
        str | None,
        typer.Option("--google-analytics", help="Include the provided Google Analytics ID on all pages."),
    ] = None,
    google_site_verification: Annotated[
        str | None,
        typer.Option(
            "--google-site-verification",
            help="Include the provided Google site verification code on all pages.",
        ),
    ] = None,
    include_osano: Annotated[
        bool,
        typer.Option(
            "--include-osano/--no-include-osano",
            envvar="ATTACK_WEBSITE_INCLUDE_OSANO",
            show_envvar=True,
            help="Include or exclude the Osano privacy compliance script.",
        ),
    ] = False,
) -> None:
    """Build the ATT&CK website."""
    if all_extras and extra_modules is not None:
        raise typer.BadParameter("--all-extras cannot be combined with --extras")

    args = SimpleNamespace(
        no_stix_link_replacement=no_stix_link_replacement,
        modules=[value.value for value in modules_to_run] if modules_to_run else module_choices,
        extras=extras
        if all_extras
        else ([value.value for value in extra_modules] if extra_modules is not None else None),
        tests=[value.value for value in selected_tests] if selected_tests is not None else None,
        attack_brand=attack_brand,
        proxy=proxy,
        subdirectory=subdirectory,
        print_tests=print_tests,
        override_exit_status=not test_exitstatus,
        version_archive_dir=version_archive_dir,
        banner=banner,
        banner_enabled=banner_enabled,
        banner_enabled_explicit=ctx.get_parameter_source("banner_enabled").name != "DEFAULT",
        google_analytics=google_analytics,
        google_site_verification=google_site_verification,
        include_osano=include_osano,
    )
    site_config.args = args
    run_build(args)


def remove_from_build(arg_modules, arg_extras):
    """Given a list of modules from command line, remove modules that appear in module directory that are not in list."""

    def remove_from_running_pool():
        """Remove modules from running pool if they are not in modules list from argument."""
        copy_of_modules = []

        for module in modules.run_ptr:
            if module["module_name"].lower() in arg_modules:
                copy_of_modules.append(module)

        modules.run_ptr = copy_of_modules

    def remove_from_menu():
        """Remove modules from menu if they are not in modules list from argument."""
        copy_of_menu = []

        for module in modules.menu_ptr:
            if module["module_name"].lower() in arg_modules:
                copy_of_menu.append(module)

        modules.menu_ptr = copy_of_menu

    # Only add extra modules if argument flag was used
    if arg_extras:
        arg_modules = arg_modules + arg_extras

    remove_from_running_pool()
    remove_from_menu()


def run_build(args):
    """Run the website build with parsed command-line arguments."""
    # Remove modules from build
    remove_from_build(args.modules, args.extras)

    # Print only the modules that will be run, marking extras
    logger.info("Building website using the following modules in this order:")
    for m in modules.run_ptr:
        mod_name = m["module_name"]
        if mod_name.lower() in extras:
            logger.info(f"{mod_name} [extra]")
        else:
            logger.info(f"{mod_name}")

    # Arguments used for pelican
    site_config.send_to_pelican("no_stix_link_replacement", args.no_stix_link_replacement)

    # Start time of update
    update_start = time.time()

    # Get running modules and priorities
    for ptr in modules.run_ptr:
        logger.info(f"RUNNING MODULE: {ptr['module_name']}")
        start_time = time.time()
        ptr["run_module"]()
        end_time = time.time()
        logger.info(f"FINISHED MODULE: {ptr['module_name']} in {end_time - start_time:.2f} seconds")

    # Print end of module
    update_end = time.time()
    logger.info(f"TOTAL Update Time: {update_end - update_start:.2f} seconds")


def main():
    """Entry point for the update script."""
    app()


if __name__ == "__main__":
    main()
