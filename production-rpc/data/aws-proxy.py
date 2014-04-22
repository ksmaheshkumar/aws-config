#!/usr/bin/env python

"""This CGI script takes care of reverse proxying to our CloudSearch server
during publishes.
 
The basic algorithm implemented here is:

 1. Reconstruct as much of the original HTTP request as we can with the
    information provided through CGI.
 2. Form up arguments that we can pass into curl to send along the request (and
    spill out the response to stdout when it comes).
 3. Turn into curl.

This is an honest-to-goodness CGI script and therefore there is a high
likelihood of security problems. Make sure our security occurs outside of this
script (achieved currently with a high-entropy, secret URL).

We would like to be able to use lighttpd to reverse proxy for us (rather than
dust off our cgi skills), but this is unfortunately not feasible. Bringing in a
web server that could do this for us such as nginx or Apache would bring a
too-high maintenance cost with it. See http://phabricator.khanacademy.org/T2427
for more information about this decision.
"""

import os
import re
import sys

# A regular expression that can pull out the part of the path that we should
# pass through to CloudSearch. For example, if the user requested
# "/cloudsearch/secure-update/supersecret/bla" this regex should match "bla".
PASSTHROUGH_RE = r"/cloudsearch/secure-update/[^/]+/(.*)"

# This file contains the HTTP endpoint we're reverse proxying
ENDPOINT_CONFIG = (
    "/home/ubuntu/aws-config/production-rpc/data/cloudsearch-publish-endpoint")


def get_headers(env=os.environ):
    """Reconstruct HTTP headers from CGI.

    Scans through the CGI environment to find most of the HTTP headers for
    the original request, and returns them all as a dictionary.
    """
    BLACKLIST = {"HOST", "CONTENT-LENGTH"}
    PREFIX = "HTTP_"
    headers = {}
    for k, v in env.iteritems():
        k = k.upper()
        if k.startswith(PREFIX):
            # Get rid of the prefix and replace underscores with dashes. For
            # example, HTTP_CONTENT_TYPE turns into CONTENT-TYPE.
            k = k[len(PREFIX):].replace("_", "-")

            if k not in BLACKLIST:
                headers[k] = v

    headers["CONTENT-TYPE"] = env.get("CONTENT_TYPE", "application/json")

    return headers


def main():
    # This could be something like
    # /cloudsearch/secure-update/secret/document/update
    request_path = os.environ["REQUEST_URI"]
    passthrough_path = re.match(PASSTHROUGH_RE, request_path).group(1)

    # Grabs our upstream server from our configuration
    with open(ENDPOINT_CONFIG, "r") as f:
        publish_endpoint = f.read().strip()

    # This will end up with something like
    # http://bla.cloudsearch.com/document/update
    url = "{endpoint}/{passthrough}".format(endpoint=publish_endpoint,
        passthrough=passthrough_path)

    current_headers = get_headers()

    # All the arguments we'll pass into curl
    curl_args = []

    # Add all of our headers in
    for k, v in current_headers.iteritems():
        curl_args += ["--header", "{}: {}".format(k, v)]

    # This will have curl print out the response headers it receives,
    # effectively making its output a valid HTTP response (which is precsiely
    # what we want).
    curl_args.append("--include")

    # Suppress the progress meter (but still output errors to stderr).
    curl_args += ["--silent", "--show-error"]

    # Keep our request from taking forever, time is in seconds
    curl_args += ["--max-time", "60"]

    # Have curl pull the POST data from standard input
    curl_args += ["--data", "@-"]

    curl_args += ["--", url]

    # This will shove the arguments into our breakage log
    print >> sys.stderr, "Executing curl with", curl_args
    sys.stderr.flush()

    # Will not return
    os.execvp("curl", ["curl"] + curl_args)


if __name__ == "__main__":
    main()
