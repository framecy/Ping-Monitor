/**
 * PingMonitor Landing Page Logic (v5)
 * Enhanced with stagger animations, navbar scroll, timeline toggle, and filter.
 */

/* ========================================
   GitHub API — Latest Release Badge
   ======================================== */
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
        }
    } catch (err) {
        console.warn('API Error:', err);
        if (heroBadge) {
            heroBadge.innerText = 'Latest Release';
        }
    }
}

/* ========================================
   Scroll Reveal with Stagger
   ======================================== */
function initReveal() {
    let staggerIndex = 0;

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                // Add a stagger delay based on order
                const delay = staggerIndex * 80;
                staggerIndex++;

                entry.target.style.animationDelay = `${delay}ms`;
                entry.target.classList.add('reveal');
                observer.unobserve(entry.target);
            }
        });
    }, {
        threshold: 0.08,
        rootMargin: '0px 0px -40px 0px'
    });

    document.querySelectorAll('.animate-fade-in').forEach(el => {
        el.classList.add('init-hide');
        observer.observe(el);
    });
}

/* ========================================
   Sticky Navbar
   ======================================== */
function initNavbar() {
    const navbar = document.getElementById('navbar');
    if (!navbar) return;

    let lastScroll = 0;

    window.addEventListener('scroll', () => {
        const currentScroll = window.scrollY;

        if (currentScroll > 60) {
            navbar.classList.add('scrolled');
        } else {
            navbar.classList.remove('scrolled');
        }

        lastScroll = currentScroll;
    }, { passive: true });
}

/* ========================================
   Bento & Background Mouse Tracking
   ======================================== */
function initTracking() {
    const root = document.documentElement;

    document.addEventListener('mousemove', (e) => {
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

/* ========================================
   Timeline Toggle (Changelog Page)
   ======================================== */
function toggleTimeline(headerEl) {
    const card = headerEl.closest('.timeline-card');
    const body = card.querySelector('.timeline-body');
    const toggle = card.querySelector('.timeline-toggle');

    if (body.classList.contains('open')) {
        body.classList.remove('open');
        toggle.classList.remove('expanded');
    } else {
        body.classList.add('open');
        toggle.classList.add('expanded');
    }
}

/* ========================================
   Changelog Filter
   ======================================== */
function initChangelogFilter() {
    const filterBtns = document.querySelectorAll('.filter-btn');
    const timelineItems = document.querySelectorAll('.timeline-item');

    if (!filterBtns.length || !timelineItems.length) return;

    filterBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            // Update active state
            filterBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');

            const filter = btn.dataset.filter;

            timelineItems.forEach(item => {
                if (filter === 'all') {
                    item.style.display = '';
                    return;
                }

                const categories = item.dataset.categories || '';
                if (categories.includes(filter)) {
                    item.style.display = '';
                } else {
                    item.style.display = 'none';
                }
            });
        });
    });
}

/* ========================================
   Smooth Anchor Scrolling
   ======================================== */
function initSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', (e) => {
            const targetId = anchor.getAttribute('href');
            if (targetId === '#') return;

            const target = document.querySelector(targetId);
            if (!target) return;

            e.preventDefault();
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        });
    });
}

/* ========================================
   Initialize
   ======================================== */
document.addEventListener('DOMContentLoaded', () => {
    fetchLatestRelease();
    initReveal();
    initNavbar();
    initTracking();
    initSmoothScroll();
    initChangelogFilter();

    // Auto-expand the first timeline item on changelog page
    const firstBody = document.querySelector('.timeline-body.open');
    if (firstBody) {
        const toggle = firstBody.closest('.timeline-card').querySelector('.timeline-toggle');
        if (toggle) toggle.classList.add('expanded');
    }
});
