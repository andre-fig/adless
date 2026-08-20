# Third-party blocklists

The MVP uses one enabled source: **OISD Small**.

- Original source: <https://small.oisd.nl/>
- Project homepage: <https://oisd.nl>
- Maintainer: Stephan van Ruth
- License: GNU General Public License v3.0, as published by OISD at <https://github.com/sjhgvr/oisd/blob/main/LICENSE>
- Included-list information: <https://oisd.nl/includedlists/small>

The source is an Adblock Plus filter list. The generator extracts only exact
domain rules in the `||domain^` form and publishes one canonical ASCII/Punycode
domain per line. Executable filter syntax is never shipped to or evaluated by
the iOS app.

The OISD license and the paid App Store distribution model must be reviewed by
the project owner/legal counsel before commercial release. Any future source
must be documented here with its original URL, maintainer, and license before it
is enabled in `tools/blocklists/sources.json`.
