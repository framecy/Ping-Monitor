/**
 * PingMonitor Landing Page Logic (v7)
 * Hero sparkline, latency tickers, parallax, counter animations, dimension bars.
 */

/* ========================================
   i18n — Translations
   ======================================== */
const i18n = {
    en: {
        'nav.features':        'Features',
        'nav.changelog':       'Changelog',
        'hero.title':          '<span class="word-network">Network.</span><br><span class="word-nuanced">Nuanced.</span>',
        'hero.desc':           'Every millisecond. Every hop. Every host. PingMonitor turns raw network noise into a precise, living dashboard — right in your menu bar.',
        'hero.download':       'Download for macOS',
        'hero.explore':        'Explore the Repo',
        'stats.tests':         'Unit Tests',
        'stats.concurrency':   'Strict Concurrency',
        'stats.platform':      'Native',
        'stats.license':       'Open Source',
        'stats.version':       'Latest Version',
        'mockup.online':       'Online',
        'mockup.offline':      'Offline',
        'mockup.quality':      'Quality Score',
        'mockup.avg':          'avg',
        'preview.eyebrow':     'Interactive Preview',
        'preview.title':       'See it in action.',
        'preview.desc':        'Real-time probes, six-dimension scoring, and visual hop-by-hop routing — all from your menu bar.',
        'preview.monitor.title':   'Monitor',
        'preview.monitor.caption': 'Live latency tickers across all hosts',
        'preview.quality.title':   'Quality',
        'preview.quality.caption': 'Six-dimension score breakdown',
        'preview.trace.title':     'Traceroute',
        'preview.trace.caption':   'Hop-by-hop path visualization',
        'preview.trace.hops':      'hops',
        'dim.latency':    'Latency',
        'dim.stability':  'Stability',
        'dim.path':       'Path',
        'dim.bandwidth':  'Bandwidth',
        'dim.resolution': 'Resolution',
        'dim.overlay':    'Overlay',
        'bento.pulse.title':   'The Pulse',
        'bento.pulse.desc':    'Concurrent ICMP probes across your entire infrastructure. Per-host quality scores (0–100) grade latency, stability, path, bandwidth, and resolution in real time — with score degradation alerts and P99 latency displayed directly on each host card.',
        'bento.flow.title':    'Flow. Measured.',
        'bento.flow.desc':     'Quality Assessment dashboard with 1 min / 5 min / 1 hour windows. Bézier-curved trend charts with jitter trend badge, donut graphs, latency rankings, and per-dimension scoring standards — all in one screen.',
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
        'hero.title':          '<span class="word-network">网络。</span><br><span class="word-nuanced">精细。</span>',
        'hero.desc':           '每一毫秒。每一跳。每一台主机。PingMonitor 将原始网络噪声转化为精准、鲜活的仪表盘——就在你的菜单栏里。',
        'hero.download':       '下载 macOS 版',
        'hero.explore':        '查看源码',
        'stats.tests':         '单元测试',
        'stats.concurrency':   '严格并发',
        'stats.platform':      '原生',
        'stats.license':       '开源',
        'stats.version':       '最新版本',
        'mockup.online':       '在线',
        'mockup.offline':      '离线',
        'mockup.quality':      '质量评分',
        'mockup.avg':          '均值',
        'preview.eyebrow':     '交互预览',
        'preview.title':       '实际效果一览',
        'preview.desc':        '实时探测、六维评分与逐跳可视化路由——一切尽在菜单栏。',
        'preview.monitor.title':   '监控',
        'preview.monitor.caption': '所有主机实时延迟跳动',
        'preview.quality.title':   '质量',
        'preview.quality.caption': '六维评分详细分解',
        'preview.trace.title':     '路由追踪',
        'preview.trace.caption':   '逐跳路径可视化',
        'preview.trace.hops':      '跳',
        'dim.latency':    '延迟',
        'dim.stability':  '稳定性',
        'dim.path':       '路径',
        'dim.bandwidth':  '带宽',
        'dim.resolution': '解析',
        'dim.overlay':    '覆盖',
        'bento.pulse.title':   '脉搏监控',
        'bento.pulse.desc':    '并发 ICMP 探测覆盖全部主机。每台主机实时显示质量评分（0–100），支持评分下降告警与 P99 延迟展示，从延迟、稳定性、路径、带宽和 DNS 解析五个维度量化网络健康状态。',
        'bento.flow.title':    '流量可量化',
        'bento.flow.desc':     '质量评估仪表盘支持 1 分钟 / 5 分钟 / 1 小时三个时间窗口。带抖动趋势徽章的贝塞尔趋势曲线、环形图、延迟排行榜与各维度评分标准，一屏全览。',
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
    const statVersion = document.getElementById('stat-version');

    try {
        const response = await fetch('https://api.github.com/repos/framecy/Ping-Monitor/releases/latest');
        if (!response.ok) return;

        const data = await response.json();
        const tag = data.tag_name;
        const dmg = data.assets.find(a => a.name.endsWith('.dmg'));

        if (heroBadge) heroBadge.innerText = `Latest Release: ${tag}`;
        if (statVersion) statVersion.textContent = tag;

        if (dmg && downloadBtn) {
            downloadBtn.href = dmg.browser_download_url;
        }
    } catch (err) {
        console.warn('API Error:', err);
        if (heroBadge) heroBadge.innerText = 'Latest Release';
    }
}

/* ========================================
   Hero Sparkline — requestAnimationFrame canvas
   ======================================== */
function initSparkline() {
    const canvas = document.getElementById('hero-sparkline');
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    const W = canvas.width;
    const H = canvas.height;
    let t = 0;

    function draw() {
        ctx.clearRect(0, 0, W, H);

        ctx.beginPath();
        const pts = 120;
        for (let i = 0; i <= pts; i++) {
            const x = (i / pts) * W;
            // Composite wave: slow base + faster jitter + very fast noise
            const y = H / 2
                - Math.sin(i * 0.08 + t * 0.6) * (H * 0.22)
                - Math.sin(i * 0.21 + t * 1.3) * (H * 0.10)
                - Math.sin(i * 0.55 + t * 2.1) * (H * 0.05);

            if (i === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
        }

        const grad = ctx.createLinearGradient(0, 0, W, 0);
        grad.addColorStop(0, 'rgba(59,130,246,0)');
        grad.addColorStop(0.2, 'rgba(59,130,246,0.7)');
        grad.addColorStop(0.8, 'rgba(34,211,238,0.7)');
        grad.addColorStop(1, 'rgba(34,211,238,0)');

        ctx.strokeStyle = grad;
        ctx.lineWidth = 1.5;
        ctx.stroke();

        t += 0.012;
        requestAnimationFrame(draw);
    }

    draw();
}

/* ========================================
   Latency Tickers — fluctuate .mh-latency and .pv-lat-tick
   ======================================== */
function initLatencyTickers() {
    function fluctuate(base) {
        const jitter = Math.floor((Math.random() - 0.5) * base * 0.5);
        return Math.max(1, base + jitter);
    }

    setInterval(() => {
        // Hero mockup latencies
        document.querySelectorAll('.mockup-host:not(.mockup-host-offline) .mh-latency').forEach(el => {
            const host = el.closest('.mockup-host');
            const base = parseInt(host.dataset.base, 10);
            if (!base) return;
            const val = fluctuate(base);
            el.textContent = `${val} ms`;
        });

        // Preview panel latencies
        document.querySelectorAll('.pv-lat-tick').forEach(el => {
            const base = parseInt(el.dataset.base, 10);
            if (!base) return;
            el.textContent = fluctuate(base);
        });
    }, 1400);
}

/* ========================================
   Stats Bar — scroll-triggered counter animation
   ======================================== */
function initCounters() {
    const counters = document.querySelectorAll('[data-count]');
    if (!counters.length) return;

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (!entry.isIntersecting) return;
            observer.unobserve(entry.target);

            const el = entry.target;
            const target = parseInt(el.dataset.count, 10);
            const duration = 1200;
            const start = performance.now();

            function step(now) {
                const elapsed = now - start;
                const progress = Math.min(elapsed / duration, 1);
                // Ease-out cubic
                const eased = 1 - Math.pow(1 - progress, 3);
                el.textContent = Math.round(eased * target);
                if (progress < 1) requestAnimationFrame(step);
            }

            requestAnimationFrame(step);
        });
    }, { threshold: 0.5 });

    counters.forEach(el => observer.observe(el));
}

/* ========================================
   Parallax — hero mockup shifts up on scroll
   ======================================== */
function initParallax() {
    const mockup = document.getElementById('hero-mockup');
    if (!mockup) return;

    window.addEventListener('scroll', () => {
        const y = window.scrollY;
        mockup.style.transform = `translateY(${-y * 0.12}px)`;
    }, { passive: true });
}

/* ========================================
   Preview Strip — dimension bars animate in on scroll
   ======================================== */
function initPreviewBars() {
    const bars = document.querySelectorAll('.pv-dim-bar');
    if (!bars.length) return;

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (!entry.isIntersecting) return;
            // Animate all bars once the quality panel enters view
            bars.forEach((bar, i) => {
                const w = bar.dataset.w || '0';
                setTimeout(() => {
                    bar.style.transition = 'width 0.7s cubic-bezier(0.22,1,0.36,1)';
                    bar.style.width = `${w}%`;
                }, i * 80);
            });
            observer.disconnect();
        });
    }, { threshold: 0.3 });

    const panel = document.getElementById('pv-quality');
    if (panel) observer.observe(panel);
}

/* ========================================
   Preview Panel — mouse glow tracking
   ======================================== */
function initPreviewTracking() {
    document.querySelectorAll('.preview-panel-inner').forEach(panel => {
        panel.addEventListener('mousemove', (e) => {
            const rect = panel.getBoundingClientRect();
            panel.style.setProperty('--mouse-x', `${e.clientX - rect.left}px`);
            panel.style.setProperty('--mouse-y', `${e.clientY - rect.top}px`);
        });
    });
}

/* ========================================
   Scroll Reveal with Stagger
   ======================================== */
function initReveal() {
    let staggerIndex = 0;

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
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

    window.addEventListener('scroll', () => {
        if (window.scrollY > 60) navbar.classList.add('scrolled');
        else navbar.classList.remove('scrolled');
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
            item.style.setProperty('--mouse-x', `${e.clientX - rect.left}px`);
            item.style.setProperty('--mouse-y', `${e.clientY - rect.top}px`);
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
            filterBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');

            const filter = btn.dataset.filter;

            timelineItems.forEach(item => {
                if (filter === 'all') {
                    item.style.display = '';
                    return;
                }
                const categories = item.dataset.categories || '';
                item.style.display = categories.includes(filter) ? '' : 'none';
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
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
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
    initSparkline();
    initLatencyTickers();
    initCounters();
    initParallax();
    initPreviewBars();
    initPreviewTracking();

    // Auto-expand the first timeline item on changelog page
    const firstBody = document.querySelector('.timeline-body.open');
    if (firstBody) {
        const toggle = firstBody.closest('.timeline-card').querySelector('.timeline-toggle');
        if (toggle) toggle.classList.add('expanded');
    }
});
