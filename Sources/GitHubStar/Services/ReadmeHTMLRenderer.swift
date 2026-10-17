import Foundation

enum ReadmeHTMLRenderer {
    static func page(for document: ReadmeDocument) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http: data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-src 'none'">
        <style>
        :root { color-scheme: light dark; --border: #d1d9e0; --muted: #59636e; --subtle: #f6f8fa; --link: #0969da; }
        @media(prefers-color-scheme: dark) { :root { --border: #3d444d; --muted: #9198a1; --subtle: #212830; --link: #4493f8; } }
        html, body { margin: 0; padding: 0; background: transparent; overflow-wrap: anywhere; }
        body { font: 14px/1.65 -apple-system, BlinkMacSystemFont, sans-serif; }
        #readme-content { display: flow-root; min-width: 0; padding: 1px 0 12px; }
        #readme-content > :first-child, .markdown-body > :first-child { margin-top: 0 !important; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.3em 0 .65em; }
        h1 { font-size: 1.85em; } h2 { font-size: 1.5em; } h3 { font-size: 1.2em; }
        h1, h2 { border-bottom: 1px solid var(--border); padding-bottom: .3em; }
        p, ul, ol, blockquote, pre, table, details { margin: 0 0 16px; }
        a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
        img, picture, video, svg { max-width: 100%; } img { height: auto; vertical-align: middle; }
        code, pre { font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
        code { background: var(--subtle); border-radius: 4px; padding: .15em .35em; }
        pre { background: var(--subtle); border-radius: 8px; padding: 14px; overflow-x: auto; white-space: pre; }
        pre code { padding: 0; background: transparent; overflow-wrap: normal; }
        table { display: block; max-width: 100%; overflow-x: auto; border-collapse: collapse; }
        th, td { padding: 7px 12px; border: 1px solid var(--border); }
        tr:nth-child(even) { background: var(--subtle); }
        blockquote { color: var(--muted); border-left: 3px solid var(--border); padding-left: 14px; }
        ul, ol { padding-left: 1.8em; } li + li { margin-top: 4px; } li > p { margin: 4px 0; }
        .task-list-item { list-style-type: none; } input[type=checkbox] { margin-right: 6px; }
        summary { cursor: pointer; font-weight: 600; } details[open] > summary { margin-bottom: 12px; }
        hr { border: 0; border-top: 1px solid var(--border); margin: 22px 0; }
        .anchor { display: none; } .markdown-alert { padding: 10px 14px; border-left: 3px solid var(--link); }
        .octicon { fill: currentColor; vertical-align: text-bottom; }
        </style></head><body><main id="readme-content">\(document.html)</main></body></html>
        """
    }

    // This app-owned script runs in an isolated world. README scripts remain disabled.
    static func script(for document: ReadmeDocument) throws -> String {
        let settings = ["id": document.id.uuidString, "linkBase": document.linkBaseURL.absoluteString,
                        "linkRoot": document.linkRootURL.absoluteString, "imageBase": document.imageBaseURL.absoluteString,
                        "imageRoot": document.imageRootURL.absoluteString, "repository": document.repositoryURL.absoluteString]
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        return """
        (() => {
          const settings = \(json);
          if (window.__githubStarReadmeID === settings.id) return;
          const root = document.getElementById('readme-content');
          function resolve(value, image) {
            if (!value || value.startsWith('#')) return value;
            if (/^[a-z][a-z0-9+.-]*:/i.test(value) || value.startsWith('//')) return value;
            if (value.startsWith('/user-attachments/') || value.startsWith('/attachments/') ||
                value.startsWith(new URL(settings.repository).pathname + '/')) return 'https://github.com' + value;
            const base = image ? settings.imageBase : settings.linkBase;
            const origin = image ? settings.imageRoot : settings.linkRoot;
            return new URL(value.replace(/^\\//, ''), value.startsWith('/') ? origin : base).href;
          }
          root.querySelectorAll('a[href]').forEach(a => a.setAttribute('href', resolve(a.getAttribute('href'), false)));
          root.querySelectorAll('img[src]').forEach(img => {
            const resolved = resolve(img.getAttribute('src'), true);
            if (resolved) img.setAttribute('src', resolved);
            img.removeAttribute('loading');
          });
          root.querySelectorAll('[srcset]').forEach(element => {
            const value = element.getAttribute('srcset');
            if (!value || value.startsWith('data:')) return;
            element.setAttribute('srcset', value.split(',').map(part => {
              const pieces = part.trim().split(/\\s+/);
              pieces[0] = resolve(pieces[0], true);
              return pieces.join(' ');
            }).join(', '));
          });
          function send(values) { window.webkit.messageHandlers.readmeEvents.postMessage(Object.assign({id: settings.id}, values)); }
          function report() { send({height: Math.ceil(root.getBoundingClientRect().height)}); }
          new ResizeObserver(report).observe(root);
          window.addEventListener('load', report);
          root.addEventListener('load', report, true);
          root.addEventListener('toggle', report, true);
          root.addEventListener('wheel', event => {
            if (event.ctrlKey || event.metaKey || event.deltaY === 0 || Math.abs(event.deltaX) > Math.abs(event.deltaY)) return;
            event.preventDefault();
            send({wheel: event.deltaY, wheelMode: event.deltaMode});
          }, {passive: false});
          root.addEventListener('click', event => {
            const link = event.target.closest('a[href]');
            if (!link) return;
            const value = link.getAttribute('href');
            if (!value || !value.startsWith('#')) return;
            event.preventDefault();
            let id;
            try { id = decodeURIComponent(value.slice(1)); } catch (_) { return; }
            const target = document.getElementById(id) || document.getElementById('user-content-' + id);
            if (target) send({scroll: target.getBoundingClientRect().top + window.scrollY});
          });
          report();
          window.__githubStarReadmeID = settings.id;
        })();
        """
    }
}
