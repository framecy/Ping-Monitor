/**
 * PingMonitor Landing Page Logic (v6)
 * Enhanced with stagger animations, navbar scroll, timeline toggle, filter, and i18n.
 */

/* ========================================
   i18n — Translations
   ======================================== */
const i18n = {
    en: {
        'nav.features':        'Features',
        'nav.changelog':       'Changelog',
        'hero.title':          'Network.<br>Nuanced.',
        'hero.desc':           'The native heartbeat of your network. Experience every millisecond with precision, visualized with elegance on macOS.',
        'hero.download':       'Download for macOS',
        'hero.explore':        'Explore the Repo',
        'stats.tests':         'Unit Tests',
        'stats.concurrency':   'Strict Concurrency',
        'stats.platform':      'Native',
        'stats.license':       'Open Source',
        'bento.pulse.title':   'The Pulse',
        'bento.pulse.desc':    'Concurrent ICMP probes across your entire infrastructure. Per-host quality scores (0–100) grade latency, stability, path, bandwidth, and resolution in real time — displayed directly on each host card.',
        'bento.flow.title':    'Flow. Measured.',
        'bento.flow.desc':     'Quality Assessment dashboard with 1 min / 5 min / 1 hour windows. Bézier-curved trend charts, donut graphs, latency rankings, and per-dimension scoring standards — all in one screen.',
        'bento.trace.title':   'The Path Forward',
        'bento.trace.desc':    'Visual traceroute and continuous MTR. A geographic hop-by-hop journey from your local IP to the global edge — no repeated password prompts, ever.',
        'bento.widget.title':  'Always Present',
        'bento.widget.desc':   'Small, medium, and large WidgetKit extensions with live host data. Menu bar shows average, worst, fastest, or a specific host — in a monospaced, jitter-free layout.',
        'bento.quick.title':   'Quick Actions',
        'bento.quick.desc':    'Web, SSH, and custom service shortcuts grouped by host. Tailscale node commands, exit-node switching, and Bark remote push notifications — one click away.',
        'spec.lang.title':     'Language',
        'spec.lang.desc':      'Swift 6 · Strict Concurrency',
        'spec.arch.title':     'Architecture',
        'spec.arch.desc':      'MVVM · @MainActor · Apple Silicon',
        'spec.int.title':      'Integrations',
        'spec.int.desc':       'Tailscale · WidgetKit · ServiceManagement',
        'spec.quality.title':  'Quality Engine',
        'spec.quality.desc':   '6-Dimension Scoring · 4096-sample Ring',
        'footer.desc':         'The native heartbeat of your network. Built with pure Swift for macOS.',
        'footer.product':      'Product',
        'footer.download':     'Download',
        'footer.changelog':    'Changelog',
        'footer.features':     'Features',
        'footer.resources':    'Resources',
        'footer.issues':       'Issues',
        'footer.license':      'MIT License',
        'footer.love':         'Built with ❤️ for macOS',
    },
    zh: {
        'nav.features':        '功能',
        'nav.changelog':       '更新日志',
        'hero.title':          '网络。<br>精细。',
        'hero.desc':           '你的网络原生心跳。以毫秒为精度感知每一次连接，在 macOS 上优雅呈现。',
        'hero.download':       '下载 macOS 版',
        'hero.explore':        '查看源码',
        'stats.tests':         '单元测试',
        'stats.concurrency':   '严格并发',
        'stats.platform':      '原生',
        'stats.license':       '开源',
        'bento.pulse.title':   '脉搏监控',
        'bento.pulse.desc':    '并发 ICMP 探测覆盖全部主机。每台主机实时显示质量评分（0–100），从延迟、稳定性、路径、带宽和 DNS 解析五个维度量化网络健康状态。',
        'bento.flow.title':    '流量可量化',
        'bento.flow.desc':     '质量评估仪表盘支持 1 分钟 / 5 分钟 / 1 小时三个时间窗口。贝塞尔趋势曲线、环形图、延迟排行榜与各维度评分标准，一屏全览。',
        'bento.trace.title':   '路由追踪',
        'bento.trace.desc':    '可视化 Traceroute 与持续 MTR 模式。从本机 IP 到目标节点的逐跳地理路径，无需重复输入管理员密码。',
        'bento.widget.title':  '始终在场',
        'bento.widget.desc':   '小、中、大三款 WidgetKit 桌面小组件，实时展示主机数据。菜单栏支持平均值、最差值、最快值或指定主机——等宽字体，无抖动布局。',
        'bento.quick.title':   '快速操作',
        'bento.quick.desc':    '按主机分组的 Web、SSH 与自定义服务快捷方式。Tailscale 节点命令、Exit Node 切换与 Bark 远程推送——一键直达。',
        'spec.lang.title':     '语言',
        'spec.lang.desc':      'Swift 6 · 严格并发',
        'spec.arch.title':     '架构',
        'spec.arch.desc':      'MVVM · @MainActor · Apple Silicon',
        'spec.int.title':      '集成',
        'spec.int.desc':       'Tailscale · WidgetKit · ServiceManagement',
        'spec.quality.title':  '质量引擎',
        'spec.quality.desc':   '六维评分 · 4096 样本环形缓冲',
        'footer.desc':         '你的网络原生心跳。纯 Swift 构建，专为 macOS 设计。',
        'footer.product':      '产品',
        'footer.download':     '下载',
        'footer.changelog':    '更新日志',
        'footer.features':     '功能',
        'footer.resources':    '资源',
        'footer.issues':       '反馈问题',
        'footer.license':      'MIT 协议',
        'footer.love':         '用 ❤️ 为 macOS 而生',
    }
};

let currentLang = localStorage.getItem('pm-lang') || 'en';

function applyLang(lang) {
    const dict = i18n[lang];
    if (!dict) return;

    document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.dataset.i18n;
        if (dict[key] !== undefined) el.textContent = dict[key];
    });

    document.querySelectorAll('[data-i18n-html]').forEach(el => {
        const key = el.dataset.i18nHtml;
        if (dict[key] !== undefined) el.innerHTML = dict[key];
    });

    const btn = document.getElementById('lang-toggle');
    if (btn) btn.textContent = lang === 'en' ? '中' : 'EN';

    document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
    currentLang = lang;
    localStorage.setItem('pm-lang', lang);
}

function toggleLang() {
    applyLang(currentLang === 'en' ? 'zh' : 'en');
}

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
    applyLang(currentLang);
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
