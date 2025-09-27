// Duende Docs helpers: copy buttons for code blocks, nav highlight, and minor UX niceties

function enhanceCodeBlocks() {
  document.querySelectorAll('pre code').forEach((code) => {
    const pre = code.parentElement;
    if (pre.querySelector('.copy-btn')) return;
    const btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.textContent = 'Copy';
    btn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(code.innerText);
        btn.textContent = 'Copied';
        setTimeout(() => (btn.textContent = 'Copy'), 1200);
      } catch (e) {
        btn.textContent = 'Error';
        setTimeout(() => (btn.textContent = 'Copy'), 1200);
      }
    });
    pre.appendChild(btn);
  });
}

function markCurrentNav() {
  const here = location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('nav a').forEach((a) => {
    const href = a.getAttribute('href');
    if (!href) return;
    if (href === here) a.classList.add('current');
  });
}

window.addEventListener('DOMContentLoaded', () => {
  enhanceCodeBlocks();
  markCurrentNav();
});
