/**
 * PingMonitor Landing Page Logic (v4)
 */

async function fetchLatestRelease() {
    const downloadBtn = document.getElementById('download-btn');
    const heroBadge = document.getElementById('hero-version-badge');

    try {
        const response = await fetch('https://api.github.com/repos/framecy/Ping-Monitor/releases/latest');
        if (!response.ok) return;

        const data = await response.json();
        const tag = data.tag_name;
        const dmg = data.assets.find(a => a.name.endsWith('.dmg'));

        if (heroBadge) {
            heroBadge.innerText = `Latest Release: ${tag}`;
        }

        if (dmg && downloadBtn) {
            downloadBtn.href = dmg.browser_download_url;
            downloadBtn.innerHTML = `Download for macOS (Apple Chip)`;
        }
    } catch (err) {
        console.warn('API Error:', err);
    }
}

// Subtle scroll reveal
function initReveal() {
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('reveal');
            }
        });
    }, { threshold: 0.1 });

    document.querySelectorAll('.animate-fade-in').forEach(el => {
        el.classList.add('init-hide');
        observer.observe(el);
    });
}

// Bento & Background Tracking
function initTracking() {
    const root = document.documentElement;

    document.addEventListener('mousemove', (e) => {
        // Global for background flashlight
        root.style.setProperty('--bg-mouse-x', `${e.clientX}px`);
        root.style.setProperty('--bg-mouse-y', `${e.clientY}px`);
    });

    document.querySelectorAll('.bento-item').forEach(item => {
        item.addEventListener('mousemove', (e) => {
            const rect = item.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;
            item.style.setProperty('--mouse-x', `${x}px`);
            item.style.setProperty('--mouse-y', `${y}px`);
        });
    });
}

document.addEventListener('DOMContentLoaded', () => {
    fetchLatestRelease();
    initReveal();
    initTracking();
});
