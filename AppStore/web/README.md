# Reps

Public pages for **Reps**, an iOS push-up counter. Served by GitHub Pages at
`https://nbretschneider.github.io/reps/`.

| Page | Purpose |
|---|---|
| `index.html` | Marketing page (App Store "Marketing URL") |
| `privacy-policy.html` | Privacy policy (App Store "Privacy Policy URL", required) |
| `support.html` | Support page (App Store "Support URL", required) |

Plain static HTML. No build step, no dependencies, no external requests, no analytics.

The source of truth for these files is `AppStore/web/` in the app repo
(`nbretschneider/reps-ios`). Edit them there and copy the result here, so the pages
and the app's submission pack cannot drift apart.

The app itself is closed source and lives in that other repo. This one exists only
because App Store Connect requires publicly reachable URLs.
