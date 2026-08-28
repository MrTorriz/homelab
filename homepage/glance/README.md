# Glance — start page

Glance runs as two sibling containers: the default instance and an
amber-themed variant. Both render the same feeds and bookmarks with a
different colour palette. Homepage links to the default instance from
its **Links** group.

| File | Container | Port (LAN) | Notes |
|---|---|---|---|
| `glance.yml` | `glance` | `8092` | Default theme, full `pages:` definition |
| `glance.amber.yml` | `glance-amber` | `8095` | Amber theme, same pages |

Earlier the dashboard had a **FEED** tab that iframed one of three
themed Glance instances (deep space / tokyo / amber) and swapped the
active iframe from custom JS to match the Homepage theme. That setup
was retired on 2026-06-21 together with the two extra instances; the
amber variant stayed as an alternative start page.

## Sharing one `pages:` definition

In the live setup, the amber variant only carries a `theme:` block and
pulls the `pages:` definition from a sibling `pages.yml` using Glance's
`$include` directive:

```yaml
pages:
  $include: pages.yml
```

The variant in this repo ships with `pages: []` and a comment so the
file is valid out of the box — copy the `pages:` block from
`glance.yml` into it, or split it into a shared file and `$include` it.

## Custom CSS

Both instances mount the same `custom.css` from
`${APPDATA_DIR}/glance/custom.css` so layout tweaks (column widths,
padding, font scaling) are written once. The CSS uses the Glance theme
variables, so colour decisions stay in the YAML.

## Screenshot

The Glance card is visible in `../../docs/img/homepage.png` (Links
group). There is no separate Glance capture.
