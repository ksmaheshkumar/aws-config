#!/usr/bin/env python

"""This is a utility for transforming a Lucene stop words dictionary into a
YAML one that `provision-domain.py` understands.

This is primarily useful when creating a stop words dictionary for a new
language. We can go and grab the default Lucene stop words dictionary and then
use that to start us off.

To find the default Lucene stop words dictionary for a particular language, see
https://svn.apache.org/repos/asf/lucene/dev/branches/preflexfixes/modules/analysis/common/src/resources/org/apache/lucene/analysis/snowball/

Instructions
------------

To use this script, pipe the Lucene dictionary into this program, the output
will be the converted dictionary.

For example, if you want to convert a Lucene dictionary at `/tmp/stopfile.txt`
and store the results into `dictionaries/english-stopwords.yaml`, you could run
the following command from your bash-like shell:

    $ cat /tmp/stopfile.txt | ./lucene-stopwords-converter.py > dictionaries/english-stopwords.yaml  # @Nolint

After you've created the YAML file, add some friendly comments to the top
explaining where you got the Lucene file from, in addition to any necessary
licensing information.

Warning
-------

This script wasn't made to be all that friendly as its use will be infrequent,
so be prepared to modify the code if anything goes awry.
"""

import sys

# This is the column that the comments will be aligned to
COMMENT_COLUMN = 28

# This string will be prepended to every word
INDENT = 4 * " "

# Starts off our YAML list
print "["

# Go through all of STDIN, line-by-line, until we hit EOF.
for line in sys.stdin:
    # Parse out the word and comment part of the line
    if "|" in line:
        word, comment = line[:line.index("|")], line[line.index("|"):]
    else:
        word, comment = line, ""

    # Strip whitespace from both (also change comment style from pipes to
    # hashes).
    word = word.strip()
    comment = comment.replace("|", "#").strip()

    if word and comment:
        # We're going to try to align the comments. Minus one for the comma.
        # Minus another 2 for the quotes
        num_spaces = COMMENT_COLUMN - len(word) - len(INDENT) - 3
        spaces = num_spaces * " "

        result = "{indent}'{word}',{spaces}{comment}".format(indent=INDENT,
            word=word, spaces=spaces, comment=comment)
    elif word and not comment:
        result = "{indent}'{word}',".format(indent=INDENT, word=word)
    elif not word and comment:
        spaces = COMMENT_COLUMN * " "
        result = "{spaces}{comment}".format(spaces=spaces, comment=comment)
    else:
        result = ""

    print result

# End our YAML list
print "]"
