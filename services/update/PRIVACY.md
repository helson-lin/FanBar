# FanBar update checks: anonymous usage statistics

简体中文：[PRIVACY.zh-CN.md](PRIVACY.zh-CN.md). If the English and Chinese versions ever differ, this English version is authoritative; please open an issue so we can fix the translation.

Operator: the FanBar project maintainers. Service: https://update.getfanbar.com. Public statistics: https://getfanbar.com/stats.

FanBar's update feed goes through `https://update.getfanbar.com/appcast.xml`. That address does one thing: it redirects (302) the request to the appcast on GitHub and records an anonymous count. If counting fails, the update check is not affected. This page explains what is recorded, what is not, and how to turn it off. The specification is [SPEC.md](SPEC.md) (Chinese) and the source code is in `src/` in this directory.

## Counted by default

Whenever the app checks for updates, the service adds 1 to the count for that app version on that day (UTC):

- The version is read from the User-Agent that Sparkle sends, of the form `FanBar/<version> Sparkle/<version>`.
- A version on the list of published releases is counted under that version. Anything else, including malformed values, is counted as `other`.
- Requests whose User-Agent is not FanBar plus Sparkle (browsers, crawlers, uptime probes) are ignored and not counted.

This needs no choice from you and carries no other field.

## Counted only when "Share anonymous usage statistics" is on

The option is off by default. New installs are asked once during onboarding; people upgrading from an earlier version are also asked once. You can change it at any time in Settings, below automatic updates, with the "Share anonymous usage statistics" switch.

When it is on, the app adds the fields below to the update check the first time it loads the appcast successfully in each UTC ISO week, at most once a week. When you turn the option on, FanBar makes that week's check right away instead of waiting for the next scheduled one. The service decides what "this week" is from its own UTC clock and does not trust a time sent by the client.

| Field | Allowed values | Notes |
| --- | --- | --- |
| `fb_cohort` (install week) | `legacy`, or a UTC ISO week such as `2026-W47` | People who upgraded from an earlier version are `legacy`; new installs send the week of their first launch (stored only on your Mac). The week must fall between the first statistics week and the current week, or it is dropped. |
| `fb_model` (Mac model) | A model identifier such as `Mac14,13`; identifiers of the right shape that are not on the known list are recorded as `other` | Values in any other format (for example, identifiers that are not Macs) are dropped. |
| `fb_os` (macOS major version) | An integer from 11 to 40 | The major version only, with no minor version or build number. |
| `fb_arch` (chip architecture) | `arm64` or `x86_64` | |
| Country or region | A two-letter country code such as `CN` | Not sent by the app. Cloudflare provides it in the request metadata, based on network location. |

Rules:

- The other fields and the country are processed only when the request carries a valid `fb_cohort`. Without it, none of them is counted.
- Each field is validated on its own. An invalid field is dropped by itself and does not affect the other fields or the version count.
- When sharing is off, the app sends no `fb_` field and the country is not recorded.

## Never collected

- No IP address is stored.
- No device ID, serial number or hardware UUID.
- No user name or host name.
- No names of other apps you have installed or run.
- No temperature history, fan speeds or any sensor readings.
- No system or interface language.
- No memory (RAM) size.
- No raw requests, raw User-Agent strings or query strings are stored.

## IP addresses and infrastructure logs

IP addresses are used only for rate limiting and are never written to the database. The service computes SHA-256 over a secret salt kept on the server together with the IP, and uses the resulting hash only as the rate limiter's key: at most 10 counts per key every 60 seconds. Requests over the limit are still redirected normally; they are just not counted. Rate limiting is a best-effort protection per Cloudflare location, and a shared network may share the allowance.

The service runs on Cloudflare. As the infrastructure provider, Cloudflare may keep request logs under its own policies while handling requests; this is outside the service's control. The service itself does not log request contents: Workers invocation logs are off, and runtime logs contain only fixed error messages without request details.

## Storage and minimum group size

The database stores only counts of the form "per day or per week × a single dimension":

- Version data is stored per day; install week, Mac model, macOS version, architecture and country are each stored per week.
- Each dimension is stored separately and never combined with another. There is no "this model in this country" combination in the database, and no record of any individual user.
- The public API and statistics page never show a group with a count below 5.

## Public statistics and retention period

The public statistics page https://getfanbar.com/stats shows update checks by version for the last 180 days, and the install-week, model, system, architecture and country distributions for the last 26 weeks. The data comes from the public API `GET https://update.getfanbar.com/api/stats`. Its response includes `minimumGroupSize: 5`, and no group smaller than 5 is ever returned.

The counts are numbers of update checks, not distinct devices or active users: a Mac that checks several times in a day is counted several times, and devices with automatic checks off or no network do not appear.

Counts in the database are kept for 730 days and then deleted by a task that runs once a day.

## How to turn it off

- Stop sharing: in Settings, below automatic updates, turn off "Share anonymous usage statistics". From then on the app sends no extra fields.
- Stop all counting: turn off automatic update checks. The app then no longer contacts the update feed on its own, so it is not counted. Choosing "Check for Updates" by hand still contacts the feed and is counted once, by version only, with no extra fields (unless you have turned sharing on).

Because no personally identifying value is stored, aggregate counts that have already been recorded cannot be withdrawn or deleted per person; they expire after 730 days.

## Source code and contact

The service's source code is public in `services/update/` in this repository: <https://github.com/helson-lin/FanBar/tree/main/services/update>. Questions are welcome in [GitHub Issues](https://github.com/helson-lin/FanBar/issues). This page is maintained alongside the source; see the Git history for changes.
