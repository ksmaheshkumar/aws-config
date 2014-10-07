#!/usr/bin/env python

"""A tool for provisioning a Khan Academy CloudSearch domain.

Additional information is available at
https://sites.google.com/a/khanacademy.org/forge/for-developers/developing-search/working-with-cloudsearch-domains

WARNING: This script will not currently delete fields. If you remove a field
from the configuration, make sure to remove the field manually by going into
the CloudSearch web console.

Instructions
------------

In order to use this tool you'll need to have the aws command line
tool installed. Get it at
http://docs.aws.amazon.com/cli/latest/userguide/installing.html

Example use: $ ./provision-domain.py khan-academy-dev domain-info.yaml

After Running the Script
------------------------

You will want to go into the Amazon Cloud Search web console to verify that all
the settings were set as expected.
https://console.aws.amazon.com/cloudsearch/
"""

import json
import logging
import optparse
import os
import pipes
import subprocess
import sys
import yaml

"""A global that is flipped within main if we're in a dry run (not actually
issuing commands to CloudSearch).
"""
dry_run = False


def parse_arguments(raw_args=sys.argv[1:]):
    """Parses any command line arguments."""
    parser = optparse.OptionParser(
        usage="usage: %prog [OPTIONS] DOMAIN_NAME DOMAIN_CONFIG_FILE",
        description="A tool for provisioning a Khan Academy CloudSearch "
            "domain.")

    parser.add_option("-v", "--verbose", action="store_true", default=False,
        help="If specified, DEBUG messages will be printed and more "
            "information will be printed with each log message.")

    parser.add_option("--leave-temp-dir", action="store_true", default=False,
        help="If specified, the created temporary directory will not be "
            "deleted when the script exits.")

    parser.add_option("-n", "--dry-run", action="store_true", default=False,
        help="If specified, no commands will actually be executed.")

    parser.add_option("--no-reindex", action="store_true", default=False,
        help="If specified, will only update the config, without reindexing.")

    options, args = parser.parse_args(raw_args)

    if len(args) != 2:
        parser.error("You must specify the name of the domain and a file "
            "containing the domain configuration.")

    return (options, args[0], args[1])


def maybe_execute_command(command, error_msg):
    """Runs a CloudSearch command (or not if its a dry run)."""

    pretty_command = command_list_to_str(command)

    # No logging here because we always log
    if dry_run:
        logging.info("Would execute: %s", pretty_command)
        return
    else:
        logging.info("Executing: %s", pretty_command)
        try:
            ret_val = subprocess.check_call(command)
        except subprocess.CalledProcessError:
            logging.exception(error_msg)
            sys.exit(1)
        return ret_val


def setup_logging(verbose):
    # Only print colors if we're working with a terminal
    if sys.stderr.isatty():
        COLOR_START = "\033[1;47m"
        COLOR_END = "\033[1;m"
    else:
        COLOR_START = ""
        COLOR_END = ""

    if verbose:
        log_level = logging.DEBUG
        format = (COLOR_START + "[%(lineno)3s - %(funcName)15s] "
            "%(levelname)5s - %(message)s" + COLOR_END)
    else:
        log_level = logging.INFO
        format = COLOR_START + "%(levelname)s - %(message)s" + COLOR_END

    logging.basicConfig(level=log_level, format=format)


def command_list_to_str(command):
    """Returns the command in such a way that it can be copy and pasted into a
    terminal.

        >>> command_list_to_str(["ls", "/some path"])
        'ls "/some path"'

    This is used in some of the log messages.
    """
    return " ".join(pipes.quote(i) for i in command)


def get_disable_flags(field_type, traits):
    """The configure tool enables all available traits by default.

    This function takes a list of desired traits (ex: ["sort", "highlight"])
    and a field_type (ex: "text") and returns a list of arguments to pass to
    define-index-field to make it so (ex: ["--return-enabled", "false",
    "--search-enabled", "false"]).

    An error is logged and `sys.exit` is called if a trait is given that is not
    available for a given field type.
    """

    # Most of the fields have the same available traits so we're going to group
    # the fields into a few categories. Each category will be called a stem.
    # The available traits are listed at
    # http://docs.aws.amazon.com/cloudsearch/latest/developerguide/configuring-index-fields.html
    # They can be verified by playing with the AWS console,
    # selecting each field type and seeing which fields are enabled.
    STEM_TO_FIELD = {
        "plain": {"int", "double", "literal", "date", "latlong"},
        "plain-array": {"int-array", "double-array", "literal-array",
            "date-array"},
        "text": {"text"},
        "text-array": {"text-array"}
    }

    # This gives the available traits for each stem
    STEM_FIELD_AVAILABLE_TRAITS = {
        "plain": {"search", "facet", "return", "sort"},
        "plain-array": {"search", "facet", "return"},
        "text": {"search", "return", "sort", "highlight"},
        "text-array": {"search", "return", "highlight"}
    }

    # Transform the field_type into its corresponding stem
    for stem, field_set in STEM_TO_FIELD.iteritems():
        if field_type in field_set:
            # stem will have the correct value when we break
            break
    else:
        logging.error("Unknown field type %r.", field_type)
        sys.exit(1)

    # Figure out the available traits for field_type
    defaults = STEM_FIELD_AVAILABLE_TRAITS[stem]

    # Make sure that no unavailable traits were specified
    for i in traits:
        if i not in defaults:
            logging.error("Trait %r not available for %r fields.", i,
                field_type)
            sys.exit(1)

    # We're going to disable every default trait that wasn't specified in
    # traits.
    disabled_traits = defaults - set(traits)

    return sum([["--{}-enabled".format(i), "false"] 
        for i in disabled_traits], [])


def configure_fields(config, domain):
    """Configures all of the fields. Called by main()."""
    locales = config["locales"]
    logging.debug("Loaded locale->scheme mappings: %r", locales)

    fields = config["fields"]
    logging.debug("Loaded fields: %r", [field["name"] for field in fields])

    # A list of lists where each sublist contains all of the arguments that
    # should be passed to define-index-field to configure that field, with
    # the exception of the --domain flag.
    field_arguments = []

    for field in fields:
        new_arguments = ["--type", field["type"]]

        # Configure the traits we want (if any traits can't be applied to this
        # type of field we'll error).
        new_arguments += get_disable_flags(field["type"], field["traits"])

        # Because of the special "locale_specific" scheme we need to do some
        # fancy processing here.
        analysis_scheme = field.get("analysis_scheme")
        if analysis_scheme == "locale_specific":
            for locale, scheme in locales.iteritems():
                # Make a clone of the current arguments and add the locale
                # specific name and analysis scheme.
                cloned_arguments = list(new_arguments)
                cloned_arguments += [
                    "--analysis-scheme", scheme,
                    "--name", "{}_{}".format(field["name"], locale)
                ]

                field_arguments.append(cloned_arguments)
        else:
            if analysis_scheme:
                new_arguments += ["--analysis-scheme", analysis_scheme]

            new_arguments += ["--name", field["name"]]

            field_arguments.append(new_arguments)

    for i in field_arguments:
        # The name is always the last item in the sublist (hacky)
        name = i[-1]
        logging.info("Configuring field %r.", name)

        command = ["aws", "cloudsearch", "define-index-field", 
            "--domain-name", domain] + i

        maybe_execute_command(command,
            "Could not configure field {}.".format(name))


def make_scheme_arg(scheme):
    if 'Stopwords' in scheme['AnalysisOptions']:
        stopwords_file = scheme['AnalysisOptions']['Stopwords']
        with open(stopwords_file) as f:
            raw = f.read()
        stopwords_list = yaml.load(raw)
        scheme['AnalysisOptions']['Stopwords'] = json.dumps(stopwords_list)

    return json.dumps(scheme)


def configure_analysis_schemes(config, domain):
    """Configures all of the analysis schemes. Called by main()."""
    analysis_schemes = config["analysis_schemes"]
    logging.debug("Loaded analysis schemes %r.", analysis_schemes)

    for i in analysis_schemes:
        logging.info("Configuring analysis scheme %r.", 
            i["AnalysisSchemeName"])

        command = ["aws", "cloudsearch", "define-analysis-scheme",
            "--domain-name", domain,
            "--analysis-scheme", make_scheme_arg(i)]

        maybe_execute_command(command,
            "Could not configure analysis scheme {}.".format(
                i["AnalysisSchemeName"]))


def reindex(domain, no_reindex):
    if no_reindex:
        logging.info("The index is now in a partial state. Reindex from the "
        "console or by re-running this script.")
        return

    command = ["aws", "cloudsearch", "index-documents", "--domain-name",
        domain]
    logging.info("Running reindex.")
    maybe_execute_command(command,
            "Reindex failed.")


def main(options, domain, domain_config_path):
    try:
        with open(domain_config_path, "r") as f:
            config = yaml.load(f)
    except IOError:
        logging.exception("Could not read from file %r.", domain_config_path)
        sys.exit(1)
    except:
        logging.exception("Failed to load configuration from %r.",
            domain_config_path)
        sys.exit(1)

    # From this point onward, all relative paths should be relative from the
    # directory that contains the config file.
    os.chdir(os.path.dirname(os.path.abspath(domain_config_path)))

    global dry_run
    if options.dry_run:
        dry_run = True

    configure_analysis_schemes(config, domain)
    configure_fields(config, domain)
    reindex(domain, options.no_reindex)


if __name__ == "__main__":
    options, domain, domain_config_path = parse_arguments()

    setup_logging(options.verbose)

    main(options, domain, domain_config_path)

    sys.exit(0)
