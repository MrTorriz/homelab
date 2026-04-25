# Glance — themed feed pages

Glance runs as four sibling containers (one default + three themed
variants). Each one renders the same set of feeds and bookmarks but
with a different colour palette, and is iframed into the **FEED** tab
of the Homepage dashboard.

A small piece of custom JS in Homepage swaps the active iframe based
on the currently selected Homepage theme so the embedded feed always
matches the rest of the dashboard:

| File | Container | Port (LAN) | Iframed when |
|---|---|---|---|
| `glance.yml` | `glance` | `8092` | Default theme |
| `glance.deepspace.yml` | `glance-deepspace` | `8093` | Deep Space theme |
| `glance.tokyo.yml` | `glance-tokyo` | `8094` | Tokyo Night theme |
| `glance.amber.yml` | `glance-amber` | `8095` | Amber theme |

## Why three theme variants?

Glance applies its theme at config load, so swapping themes at runtime
means swapping config files. Running four identical-but-themed
instances is the simplest way to make the embedded feed match the
parent dashboard's selected look — disk and RAM cost is negligible
(the Glance image is ~30 MB and idle memory is a few MB per instance).

## Sharing one `pages:` definition

In the live setup, the three themed variants only carry a `theme:`
block and pull the same `pages:` definition from a sibling
`pages.yml` file using Glance's `$include` directive:

```yaml
pages:
  $include: pages.yml
```

The variants in this repo ship with `pages: []` and a comment so the
file is valid out of the box — copy the `pages:` block from
`glance.yml` into each variant, or split it into a shared file and
`$include` it.

## Custom CSS

All four instances mount the same `custom.css` from
`${APPDATA_DIR}/glance/custom.css` so layout tweaks (column widths,
padding, font scaling) are written once. The CSS uses the Glance theme
variables, so colour decisions stay in the YAML.

## Embedding into Homepage

Nginx Proxy Manager strips `X-Frame-Options` from the Glance upstream
so Homepage can iframe it on the same origin. If you self-sign or use
a non-public CA, browsers may need a one-off SSL exception for each
Glance hostname before the iframe will render — visit each subdomain
directly once and accept the certificate.

## Screenshot

A screenshot of the three themes side-by-side lives at
`../homepage.gif` (animated tab switch); a static stills variant can
be dropped into `screenshot.png` next to this README if you prefer.
