/**
 * PingMonitor Landing Page Logic
 * Fetches latest release from GitHub API
 */

const REPO_OWNER = 'framecy';
const REPO_NAME = 'Ping-Monitor';

async function fetchLatestRelease() {
    const downloadBtn = document.getElementById('download-btn');
    const badgeContainer = document.getElementById('version-badge-container');

    try {
        const response = await fetch(`https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest`);

        if (!response.ok) throw new Error('Release not found');

        const data = await response.json();
        const version = data.tag_name;

        // Find the .dmg asset
        const dmgAsset = data.assets.find(asset => asset.name.endsWith('.dmg'));

        if (dmgAsset) {
            downloadBtn.href = dmgAsset.browser_download_url;
            downloadBtn.innerHTML = `<span class="icon">↓</span> 下载最新版本 (${version})`;
        }

        // Update version badge if it exists
        if (badgeContainer) {
            badgeContainer.innerHTML = `<span class="version-badge">最新发布: ${version}</span>`;
            badgeContainer.classList.add('animate-fade-in');
        }

        console.log(`Successfully fetched latest release: ${version}`);

    } catch (error) {
        console.warn('Failed to fetch latest release from GitHub API:', error);
        // Fallback is already set in HTML to point to general releases page
    }
}

// Scroll reveal animation logic
function initScrollReveal() {
    const observerOptions = {
        threshold: 0.1
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.style.opacity = "1";
                entry.target.style.transform = "translateY(0)";
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    document.querySelectorAll('.animate-fade-in').forEach(el => {
        el.style.opacity = "0";
        el.style.transform = "translateY(20px)";
        observer.observe(el);
    });
}

// Run on load
document.addEventListener('DOMContentLoaded', () => {
    fetchLatestRelease();
    initScrollReveal();
});
