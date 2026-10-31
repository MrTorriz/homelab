# Glance — start page

Glance runs as two sibling containers: the default instance and an
amber-themed variant. Both render the same pages with a different colour
palette. Homepage links to the default instance from its **Shortcuts**
row.

| File | Container | Port (LAN) | Notes |
|---|---|---|---|
| `glance.yml` | `glance` | `8092` | Default theme, includes `pages.yml` |
| `glance.amber.yml` | `glance-amber` | `8095` | Amber theme, includes `pages.yml` |
| `pages.yml` | both | — | Sanitized shared page list |
| `custom.css` | both | — | Reading design for desktop and mobile |

## Pages

| Page | Content |
|---|---|
| Tech | r/selfhosted, r/homelab, r/linux, tech and Linux RSS, Hacker News |
| News | r/worldnews and international RSS |
| Movies & TV | r/movies, r/television and film-industry RSS |
| Finance | Market tickers, business RSS, calendar |
| Server | Uptime monitors for every service, grouped infrastructure / media / cloud & tools, plus operator shortcuts |

The live instance has a few more personal pages (sport, local news,
bookmarks); they are left out here.

## Reddit through Miniflux

Reddit rate-limits (HTTP 429) the shared VPN exit, and Glance's built-in
`reddit` widget then shows an error box. The subreddit feeds are therefore
subscribed in Miniflux, which polls them on its own schedule and keeps the
entries in Postgres when a fetch fails. Glance reads them with a
`custom-api` widget against Miniflux's API and one shared Go template (a
YAML anchor, `&reddit-list`), so the worst case is slightly stale content —
never an error box.

## Sharing one `pages:` definition

Both variants pull the page list from a sibling `pages.yml` using Glance's
`$include` directive:

```yaml
pages:
  $include: pages.yml
```

Only the `theme:` block differs between the two instance files, so pages
are edited in one place.

## Environment

`pages.yml` uses Glance's `${VAR}` substitution. Pass these to both
containers:

| Variable | Used for |
|---|---|
| `MINIFLUX_API_TOKEN` | Read-only Miniflux API token for the Reddit lists |
| `LAN_IP` | Monitor checks for the host-network services (AdGuard Home, Glances, qBittorrent) |

## Custom CSS

Both instances mount the same `custom.css` from
`${APPDATA_DIR}/glance/custom.css`. It is a reading design: a readable
news column with two equal side columns on desktop and tablet, and on
mobile a compact header, article rows on the page background and the
first headline as a larger card. It uses only Glance's theme variables —
no external fonts or scripts — so colour decisions stay in the YAML.
