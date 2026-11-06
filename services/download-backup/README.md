# Independent download backup

The Netlify production deploy stores a verified copy of the latest universal DMG at `/latest.dmg`; downloads do not depend on GitHub or Cloudflare. `/version.json` identifies the mirrored release and SHA-256. The sync workflow checks GitHub Releases on publication and hourly, verifies GitHub's asset SHA-256 and size, and deploys the snapshot atomically. Failed syncs leave the previous snapshot in place. Netlify usage limits apply.

The workflow must be installed on the default branch and requires repository secrets `NETLIFY_AUTH_TOKEN` and `NETLIFY_SITE_ID`. Never print the token. A scheduled workflow may be delayed by GitHub. Existing downloads remain available if GitHub is temporarily unavailable.
