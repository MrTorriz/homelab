# Glance — start page

Glance runs as two sibling containers: the default instance and an
amber-themed variant. Both render the same feeds and bookmarks with a
different colour palette. Homepage links to the default instance from
its **Links** group.

| File | Container | Port (LAN) | Notes |
|---|---|---|---|
| `glance.yml` | `glance` | `8092` | Default theme, includes `pages.yml` |
| `glance.amber.yml` | `glance-amber` | `8095` | Amber theme, includes `pages.yml` |
| `pages.yml` | both | — | Sanitized shared page list |
| `custom.css` | both | — | Theme-aware widget border animation |

Earlier the dashboard had a **FEED** tab that iframed one of three
themed Glance instances (deep space / tokyo / amber) and swapped the
active iframe from custom JS to match the Homepage theme. That setup
was retired on 2026-06-21 together with the two extra instances; the
amber variant stayed as an alternative start page.

## Sharing one `pages:` definition

Both variants pull the page list from a sibling `pages.yml` using Glance's
`$include` directive:

```yaml
pages:
  $include: pages.yml
```

The variant in this repo includes the published, sanitized `pages.yml`,
so the Compose example has every mounted source file it needs.

## Custom CSS

Both instances mount the same `custom.css` from
`${APPDATA_DIR}/glance/custom.css` so layout tweaks (column widths,
padding, font scaling) are written once. The CSS uses the Glance theme
variables, so colour decisions stay in the YAML.

## Screenshot

The Glance card is visible in `../../docs/img/homepage-public.png` (Links
group). There is no separate Glance capture.
