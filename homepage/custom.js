/*
 * Homepage custom.js — the live dashboard's script (2026-10-31), served
 * from /app/public/custom.js. Display-only: it never calls anything
 * outside Homepage's own API and never changes widget data.
 *
 *   1. Logo        — swaps the greeting text for an inline SVG wordmark
 *   2. Theme       — pins the palette the stylesheet keys on
 *   3. Disk bars   — colour classes from the real percentage
 *   4. Navigation  — mobile shortcuts, Ctrl/Cmd+K, accessible labels,
 *                    capacity/CPU-temperature context, metric wording
 *   5. Weather     — retries a failed weather widget once a minute
 */

/* 1. Logo: replace the greeting text "Mserver" with an inline SVG glyph. */
const BRAND_LOGO_SVG = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 274 70" class="brand-logo-svg">
  <defs>
    <linearGradient id="m-grad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="currentColor" stop-opacity="1" />
      <stop offset="100%" stop-color="currentColor" stop-opacity="0.55" />
    </linearGradient>
    <style>
      .cursor { animation: blink 1s step-end infinite; }
      @keyframes blink { 0%,50% { opacity: 1; } 51%,100% { opacity: 0; } }
    </style>
  </defs>
  <!-- terminal prompt: ~ + chevron -->
  <text x="2" y="47" font-family="JetBrains Mono, monospace" font-weight="700"
        font-size="26" fill="currentColor" opacity="0.7">~</text>
  <path d="M 28 28 L 40 38 L 28 48"
        stroke="currentColor" stroke-width="4.5" fill="none"
        stroke-linecap="round" stroke-linejoin="round" opacity="0.7" />
  <!-- M + SERVER, shifted right to leave room for the prompt -->
  <g transform="translate(52, 0)">
    <!-- M: dominant, heavier stroke with round end dots -->
    <path d="M 26 52 L 26 20 L 50 38 L 74 20 L 74 52"
          stroke="url(#m-grad)"
          stroke-width="5.5"
          fill="none"
          stroke-linecap="round"
          stroke-linejoin="round" />
    <circle cx="26" cy="52" r="2.2" fill="currentColor" />
    <circle cx="74" cy="52" r="2.2" fill="currentColor" />
    <!-- SERVER: smaller, thinner stroke -->
    <g stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round" opacity="0.85">
      <path d="M 98 30 L 86 30 L 86 38 L 98 38 L 98 46 L 86 46" />
      <path d="M 114 30 L 104 30 L 104 46 L 114 46 M 104 38 L 112 38" />
      <path d="M 120 46 L 120 30 L 132 30 L 132 38 L 120 38 L 132 46" />
      <path d="M 138 30 L 144 46 L 150 30" />
      <path d="M 166 30 L 156 30 L 156 46 L 166 46 M 156 38 L 164 38" />
      <path d="M 172 46 L 172 30 L 184 30 L 184 38 L 172 38 L 184 46" />
    </g>
  </g>
  <!-- blinking cursor after SERVER -->
  <rect class="cursor" x="254" y="24" width="13" height="26" fill="currentColor" />
</svg>`;

function applyBrandLogo() {
    // Scan only the greeting widget, not the whole DOM (the full scan caused lag).
    const scope = document.querySelector('.information-widget-greeting') || document.body;
    const elements = scope.querySelectorAll('h1, h2, p, span, div, a');
    elements.forEach(el => {
        if (el.closest('.brand-logo-wrap')) return;
        if (el.textContent.trim() === 'Mserver' && el.children.length === 0) {
            el.innerHTML = BRAND_LOGO_SVG;
            el.classList.add('brand-logo-wrap');
        }
    });
}

/* rAF debounce: collapse a burst of DOM mutations into one run per frame
   instead of running the callback for every single mutation (widgets tick
   constantly). */
function rafDebounce(fn) {
    let scheduled = false;
    return () => {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(() => { scheduled = false; fn(); });
    };
}

applyBrandLogo();
const logoObserver = new MutationObserver(rafDebounce(() => {
    // The greeting is static: disconnect as soon as the logo is in place.
    if (document.querySelector('.brand-logo-wrap')) { logoObserver.disconnect(); return; }
    applyBrandLogo();
}));
if (!document.querySelector('.brand-logo-wrap')) {
    logoObserver.observe(document.body, { childList: true, subtree: true });
}

/* 2. Theme: the stylesheet scopes its palette to data-theme="amber".
   Only one theme is left, so it is pinned rather than toggled. */
document.documentElement.setAttribute('data-theme', 'amber');

/* 3. Disk/resource bars: set colour classes from the actual value. This
   replaces a CSS substring trick ([style*="width: 8"]) that matched both
   8 % and 80 %. Bars turn red only when nearly full (95 %). */
function updateProgressBars() {
    document.querySelectorAll('.resource-usage > div[style*="width"]').forEach(bar => {
        const m = bar.style.width.match(/^(\d+(?:\.\d+)?)/);
        if (!m) return;
        const w = parseFloat(m[1]);
        bar.classList.remove('progress-warn', 'progress-danger');
        if (w >= 95) bar.classList.add('progress-danger');
    });
}

const progressObserver = new MutationObserver(rafDebounce(updateProgressBars));
progressObserver.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['style'],
});
updateProgressBars();

/* 4. Daily navigation, accessibility and status context. */
(() => {
    const launchSelector = 'button.fixed.bottom-4.right-4:has(svg circle)';
    const favourites = ['Jellyfin', 'Seerr', 'Nextcloud', 'Immich'];
    let measuredAt = null;
    let timeUnavailable = false;
    let searchWasOpen = false;
    let searchReturnFocus = null;

    const setAttribute = (element, name, value) => {
        if (element && element.getAttribute(name) !== value) element.setAttribute(name, value);
    };
    const setText = (element, value) => {
        if (element && element.textContent !== value) element.textContent = value;
    };
    const service = name => Array.from(document.querySelectorAll('#layout-groups .service'))
        .find(element => element.dataset.name === name);

    function searchButton() {
        const button = document.querySelector(launchSelector);
        if (!button) return null;
        button.classList.add('homepage-find-service');
        setAttribute(button, 'aria-hidden', 'true');
        setAttribute(button, 'tabindex', '-1');
        return button;
    }

    function mobileShortcuts() {
        const greeting = document.querySelector('.information-widget-greeting');
        if (!greeting || document.getElementById('homepage-mobile-shortcuts')) return;
        const nav = document.createElement('nav');
        nav.id = 'homepage-mobile-shortcuts';
        nav.setAttribute('aria-label', 'Daily services');
        favourites.forEach(name => {
            const source = service(name)?.querySelector('a.service-title-text');
            const icon = service(name)?.querySelector('.service-icon img');
            if (!source) return;
            const link = document.createElement('a');
            link.href = source.href;
            link.target = source.target;
            link.rel = source.rel;
            link.setAttribute('aria-label', `Open ${name}`);
            if (icon) {
                const image = icon.cloneNode(false);
                image.alt = '';
                image.removeAttribute('style');
                link.append(image);
            }
            const label = document.createElement('span');
            label.textContent = name;
            link.append(label);
            nav.append(link);
        });
        if (nav.children.length === favourites.length) greeting.after(nav);
    }

    function accessibleServices() {
        document.querySelectorAll('#layout-groups .service').forEach(item => {
            const name = item.dataset.name;
            const icon = item.querySelector('a.service-icon');
            setAttribute(icon, 'tabindex', '-1');
            setAttribute(icon, 'aria-hidden', 'true');
            item.querySelectorAll('.service-icon img').forEach(image => setAttribute(image, 'alt', ''));
            const link = item.querySelector('a.service-title-text');
            setAttribute(link, 'aria-label', `Open ${name}`);
            const description = item.querySelector('.service-description');
            if (description) {
                const id = `service-description-${name.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`;
                setAttribute(description, 'id', id);
                setAttribute(link, 'aria-describedby', id);
            }
            const button = item.querySelector('button.service-container-stats');
            const status = item.querySelector('.docker-status')?.title || 'Status unavailable';
            const stats = item.querySelector('.service-stats');
            const expanded = Boolean(stats?.classList.contains('opacity-100'));
            setAttribute(button, 'aria-label', `${name}: container ${status.toLowerCase()}. ${expanded ? 'Hide' : 'Show'} CPU and memory.`);
            const explanation = status.toLowerCase() === 'healthy' ? 'Container health check passed' : status.toLowerCase() === 'running' ? 'Container started; app functionality not verified' : 'Check container status';
            setAttribute(button, 'title', `${name} · ${explanation} · Click for CPU and memory`);
            setAttribute(button, 'aria-expanded', String(expanded));
        });
        const google = document.querySelector('.information-widget-search input');
        setAttribute(google, 'aria-label', 'Search Google');
        setAttribute(document.querySelector('[role="dialog"]:has(input[placeholder="Search"])'), 'aria-label', 'Find service');
    }

    function capacityContext() {
        // The capacity message belongs in the disk card itself, not in a separate warning row.
        const disks = Array.from(document.querySelectorAll('#widgets-wrap .information-widget-resource:has(.expanded)'));
        disks.forEach((disk, index) => {
            const name = ['SSD', 'Storage', 'Media'][index];
            const bar = disk.querySelector('.resource-usage > div');
            const used = parseFloat(bar?.style.width);
            const free = disk.querySelector('.expanded > div:first-child > div:first-child')?.textContent.trim();
            if (!name || !free || !Number.isFinite(used)) return;
            const low = used >= 95;
            const caution = low ? 'Space low; plan more space.' : used >= 90 ? 'Watch capacity.' : '';
            setAttribute(disk, 'data-capacity-label', `${name} · free`);
            setAttribute(disk.querySelector('.expanded > div:nth-child(2) > div:last-child'), 'data-used-short', `${used}%`);
            disk.classList.toggle('homepage-space-low', low);
            setAttribute(disk, 'aria-label', `${name}: ${free} free, ${used}% used. ${caution}`);
            setAttribute(disk, 'title', `${name}: ${free} free, ${used}% used. ${caution}`);
        });
    }

    // Resource cards: only display attributes; React's own text nodes are left alone.
    let cpuTemperature = null;
    let temperaturePending = true;
    function resourceContext() {
        const compact = Array.from(document.querySelectorAll('#widgets-wrap .widget-container:not(:has(.expanded)) .information-widget-resource'));
        const disks = Array.from(document.querySelectorAll('#widgets-wrap .information-widget-resource:has(>.expanded)'));
        const resources = [compact[0], compact[1], ...disks];
        resources.forEach((card, index) => {
            if (!card) return;
            const kind = ['cpu', 'memory', 'ssd', 'storage', 'media'][index];
            setAttribute(card, 'data-homepage-resource', kind);
            const value = card.querySelector(':scope > div > div:first-child > div:first-child');
            const text = value?.textContent.trim() || '';
            const match = text.match(/^(\d[\d,.]*)\s*(%|[KMGTPE]?i?B)$/);
            setAttribute(value, 'data-resource-number', match ? match[1] : text);
            setAttribute(value, 'data-resource-unit', match ? match[2] : '');
            const wrapper = card.querySelector(':scope > div');
            if (kind === 'cpu') {
                const detail = cpuTemperature === null ? (temperaturePending ? 'Loading temp…' : 'Temp unavailable') : `${cpuTemperature} °C · CPU temp`;
                setAttribute(wrapper, 'data-resource-detail', detail);
                setAttribute(card, 'aria-label', `CPU: ${text} load. ${detail}`);
                setAttribute(card, 'title', `CPU: ${text} load. ${detail}`);
            } else if (kind === 'memory') {
                const used = Number.parseFloat(card.querySelector('.resource-usage > div')?.style.width);
                const detail = Number.isFinite(used) ? `${Math.round(used)}% used` : 'Usage unavailable';
                setAttribute(wrapper, 'data-resource-detail', detail);
                setAttribute(card, 'aria-label', `RAM: ${text} free. ${detail}`);
                setAttribute(card, 'title', `RAM: ${text} free. ${detail}`);
            }
        });
    }
    async function loadCpuTemperature() {
        try {
            const response = await fetch('/api/widgets/resources?type=cputemp', { signal: AbortSignal.timeout(10000), cache: 'no-store' });
            if (!response.ok) throw new Error('Temperature unavailable');
            const data = (await response.json())?.cputemp;
            // Require per-core sensors: avoids a chipset/ACPI fallback reading on this Intel host.
            if (!Array.isArray(data?.cores) || !data.cores.some(t => Number.isFinite(t) && t > 0) || !Number.isFinite(data.main) || data.main <= 0 || data.main > 125) throw new Error('CPU sensor unavailable');
            cpuTemperature = Math.round(data.main);
        } catch {
            cpuTemperature = null; // Never show a stale temperature as current.
        }
        temperaturePending = false;
        enhance();
    }

    const overviewNumber = new Intl.NumberFormat('en-GB', {
        minimumFractionDigits: 1,
        maximumFractionDigits: 1,
    });
    function roundOverviewValue(block) {
        const value = block?.firstElementChild;
        const match = value?.textContent.trim().match(/^(-?\d[\d,]*(?:\.\d+)?)(\s*W)?$/);
        if (!match) return; // Keep loading markers and error messages as they are.
        const number = Number(match[1].replaceAll(',', ''));
        if (!Number.isFinite(number)) return;
        setText(value, overviewNumber.format(number) + (match[2] ? ' W' : ''));
    }

    function metricContext() {
        const grafana = service('Grafana');
        roundOverviewValue(grafana?.querySelector('.service-container > .service-block'));
        const tdarr = service('Tdarr');
        const blocks = tdarr?.querySelectorAll('.service-container > .service-block');
        if (blocks?.length === 2) {
            setText(blocks[0].lastElementChild, 'Jobs queued');
            setText(blocks[1].lastElementChild, 'Job errors');
            setAttribute(blocks[0], 'title', 'Transcode jobs plus health-check jobs. A file can have more than one job.');
            setAttribute(blocks[1], 'title', 'Transcode errors plus health-check errors.');
        }
        const speedtest = service('Speedtest Tracker');
        speedtest?.querySelectorAll('.service-container > .service-block').forEach(roundOverviewValue);
        const description = speedtest?.querySelector('.service-description');
        if (measuredAt) {
            const minutes = Math.max(0, Math.floor((Date.now() - measuredAt.getTime()) / 60000));
            const age = minutes < 1 ? 'just now' : minutes < 60 ? `${minutes}m ago` : minutes < 1440 ? `${Math.floor(minutes / 60)}h ago` : `${Math.floor(minutes / 1440)}d ago`;
            setText(description, `Tested ${age}`);
            setAttribute(speedtest?.querySelector('a.service-title-text'), 'title', `Speedtest measured ${measuredAt.toLocaleString('en-GB')}`);
        } else if (timeUnavailable) setText(description, 'Measurement time unavailable');
        const users = service('Nextcloud')?.querySelector('.service-container > .service-block:first-child');
        setAttribute(users, 'title', 'Users active in the last 24 hours. Files is Nextcloud’s file-index count.');
    }

    const observer = new MutationObserver(rafDebounce(enhance));
    const observation = { childList: true, characterData: true, subtree: true, attributes: true, attributeFilter: ['class', 'style', 'title'] };
    function enhance() {
        // Disconnect first so this script's own DOM changes don't trigger the next round.
        observer.disconnect();
        searchButton();
        mobileShortcuts();
        accessibleServices();
        capacityContext();
        resourceContext();
        metricContext();
        const open = Boolean(document.querySelector('[role="dialog"][aria-hidden="false"] input[placeholder="Search"]'));
        if (searchWasOpen && !open && searchReturnFocus?.isConnected) searchReturnFocus.focus({ preventScroll: true });
        searchWasOpen = open;
        observer.observe(document.body, observation);
    }
    document.addEventListener('keydown', event => {
        if (!searchWasOpen) searchReturnFocus = document.activeElement;
        if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k' && !event.altKey) {
            event.preventDefault();
            const input = document.querySelector('[role="dialog"][aria-hidden="false"] input[placeholder="Search"]');
            if (input) input.focus();
            else searchButton()?.click();
        }
    });
    async function loadMeasurementTime() {
        try {
            const params = new URLSearchParams({ group: 'Network', service: 'Speedtest Tracker', index: '0', query: '{"refreshInterval":60000}' });
            const response = await fetch(`/api/services/proxy?${params}`, { signal: AbortSignal.timeout(10000) });
            if (!response.ok) throw new Error('Measurement unavailable');
            const data = await response.json();
            const date = new Date(data?.data?.created_at);
            if (!Number.isFinite(date.getTime())) throw new Error('Measurement time missing');
            measuredAt = date;
            timeUnavailable = false;
        } catch {
            timeUnavailable = true;
            measuredAt = null;
        }
        enhance();
    }
    enhance();
    loadMeasurementTime();
    loadCpuTemperature();
    setInterval(loadMeasurementTime, 60000);
    setInterval(loadCpuTemperature, 15000);
})();

/* 5. Weather: Homepage treats an API error delivered with HTTP 200 as valid
   SWR data. On such an error, nudge the existing widget to revalidate, at
   most once a minute and only while the page is visible; the error text
   stays until the API answers correctly. */
(() => {
    let lastRetry = 0;
    function retryWeather() {
        if (document.hidden) return;
        const weatherError = document.querySelector('#information-widgets-right > .information-widget-error');
        if (!weatherError || Date.now() - lastRetry < 60000) return;
        lastRetry = Date.now();
        window.dispatchEvent(new Event('focus'));
    }
    setInterval(retryWeather, 15000);
})();
