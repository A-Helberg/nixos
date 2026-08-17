// Witchcraft loads this on every plan.coded.page URL. Wherever the page shows
// a "Properties" section, put the automation buttons under its header.
(function () {
  "use strict";

  const BAR_CLASS = "wc-button-bar";
  const BUTTON_CLASS =
    "inline-flex shrink-0 items-center justify-center text-sm font-medium whitespace-nowrap transition-all outline-none focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:pointer-events-none disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-destructive/20 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4 bg-primary text-primary-foreground shadow-xs hover:bg-primary/90 h-8 gap-1.5 rounded-md px-3 has-[>svg]:px-2.5";

  // The forgejo PR link in the Properties panel, if the item has one. Require
  // an exact .../pulls/<n> href so PR links inside comments (which carry
  // #issuecomment-… fragments) can't match.
  function forgejoPrUrl() {
    for (const a of document.querySelectorAll(
      'a[href^="https://git.coded.page/"]',
    )) {
      if (/^https:\/\/git\.coded\.page\/[^/]+\/[^/]+\/pulls\/\d+$/.test(a.href))
        return a.href;
    }
    return null;
  }

  // The "Properties" section-header buttons are the stable anchor: the page
  // renders one in the mobile layout and one in the desktop sidebar, and the
  // DOM around them shifts (sidebar toggle, viewport), so XPath is out.
  function propertiesHeaders() {
    return [...document.querySelectorAll("button")].filter(
      (b) => b.textContent.trim() === "Properties",
    );
  }

  function render() {
    const prUrl = forgejoPrUrl();

    for (const header of propertiesHeaders()) {
      let bar = header.nextElementSibling;
      if (!bar || !bar.classList.contains(BAR_CLASS)) {
        bar = document.createElement("div");
        bar.className = BAR_CLASS + " mb-3 flex flex-wrap gap-1.5";

        const dispatch = document.createElement("a");
        dispatch.href = "hammerspoon://hello";
        dispatch.className = BUTTON_CLASS;
        dispatch.textContent = "Dispatch";
        bar.appendChild(dispatch);

        header.after(bar);
      }

      // The PR can change as the SPA navigates between items, so keep the
      // hrefs current, and drop the buttons when the item has no PR. The PR
      // link is also the only element naming the repo, which "Sync from GH"
      // needs (stripped of /pulls/N) even though the PR itself is irrelevant
      // to it.
      const repoUrl = prUrl && prUrl.replace(/\/pulls\/\d+$/, "");
      for (const [attr, label, hrefFor] of [
        ["data-wc-sync", "Sync to GH", () =>
          "hammerspoon://sync-to-gh?pr=" + encodeURIComponent(prUrl)],
        ["data-wc-sync-from", "Sync from GH", () =>
          "hammerspoon://sync-from-gh?repo=" + encodeURIComponent(repoUrl)],
      ]) {
        let btn = bar.querySelector("a[" + attr + "]");
        if (prUrl) {
          if (!btn) {
            btn = document.createElement("a");
            btn.setAttribute(attr, "");
            btn.className = BUTTON_CLASS;
            btn.textContent = label;
            bar.appendChild(btn);
          }
          btn.href = hrefFor();
        } else if (btn) {
          btn.remove();
        }
      }
    }
  }

  render();

  // The app renders client-side and navigates without page loads, so keep
  // watching; this also covers moving between items.
  const observer = new MutationObserver(render);
  observer.observe(document.body, { childList: true, subtree: true });
})();
