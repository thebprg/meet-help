import SwiftUI
import WebKit

struct MarkdownRenderView: View {
    let markdown: String
    @State private var height: CGFloat = 24

    var body: some View {
        MarkdownWebView(markdown: markdown, height: $height)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .clipped()
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "height")

        let webView = PassthroughWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.loadHTMLString(Self.html(for: markdown), baseURL: nil)

        DispatchQueue.main.async {
            Self.disableScrolling(in: webView)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.markdown != markdown else { return }

        context.coordinator.markdown = markdown
        webView.loadHTMLString(Self.html(for: markdown), baseURL: nil)

        DispatchQueue.main.async {
            Self.disableScrolling(in: webView)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height")
    }

    private static func disableScrolling(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
            scrollView.scrollerStyle = .overlay
            scrollView.drawsBackground = false
            scrollView.contentView.postsBoundsChangedNotifications = false
        }

        view.subviews.forEach { disableScrolling(in: $0) }
    }

    private static func html(for markdown: String) -> String {
        let markdownJSON = jsonString(normalizedMarkdown(markdown))

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              min-height: 24px;
              background: transparent !important;
              color: rgba(255, 255, 255, 0.96);
              font: 15px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              line-height: 1.48;
              overflow: hidden !important;
            }
            * { box-sizing: border-box; }
            #content {
              width: 100%;
              padding: 0 2px 2px 2px;
              background: transparent !important;
              overflow: hidden;
              overflow-wrap: anywhere;
            }
            h1, h2, h3, h4, h5, h6 {
              margin: 0.25em 0 0.45em;
              font-weight: 650;
              line-height: 1.2;
              letter-spacing: 0;
            }
            h1 { font-size: 20px; }
            h2 { font-size: 18px; }
            h3 { font-size: 16px; }
            h4, h5, h6 { font-size: 15px; }
            p { margin: 0 0 0.65em 0; }
            p:last-child, ul:last-child, ol:last-child, pre:last-child, table:last-child { margin-bottom: 0; }
            strong { font-weight: 700; }
            em { font-style: italic; }
            del { opacity: 0.75; }
            a { color: #8ec7ff; text-decoration: none; }
            ul, ol { margin: 0.25em 0 0.75em 1.25em; padding: 0; }
            li { margin: 0.22em 0; }
            li > p { margin: 0; }
            input[type="checkbox"] { margin-right: 6px; }
            code {
              font: 13px "SF Mono", Menlo, Consolas, monospace;
              background: rgba(255, 255, 255, 0.11);
              border-radius: 4px;
              padding: 0.1em 0.25em;
            }
            pre {
              margin: 0.55em 0 0.85em 0;
              padding: 9px;
              background: rgba(0, 0, 0, 0.22);
              border: 1px solid rgba(255, 255, 255, 0.10);
              border-radius: 6px;
              overflow: hidden;
              white-space: pre-wrap;
              word-break: break-word;
            }
            pre code {
              display: block;
              padding: 0;
              background: transparent;
              border-radius: 0;
              white-space: pre-wrap;
            }
            blockquote {
              margin: 0.6em 0;
              padding: 0.1em 0 0.1em 0.8em;
              border-left: 3px solid rgba(255, 255, 255, 0.28);
              color: rgba(255, 255, 255, 0.84);
            }
            table {
              border-collapse: collapse;
              width: 100%;
              table-layout: fixed;
              margin: 0.7em 0;
              font-size: 13px;
            }
            th, td {
              border: 1px solid rgba(255, 255, 255, 0.16);
              padding: 5px 7px;
              text-align: left;
              word-break: break-word;
              vertical-align: top;
            }
            th { background: rgba(255, 255, 255, 0.10); }
            hr {
              border: 0;
              border-top: 1px solid rgba(255, 255, 255, 0.18);
              margin: 0.9em 0;
            }
            img {
              max-width: 100%;
              height: auto;
              border-radius: 6px;
            }
            .math-fallback {
              font-family: Georgia, "Times New Roman", serif;
              white-space: pre-wrap;
            }
            .mermaid {
              max-width: 100%;
              padding: 8px;
              background: rgba(255, 255, 255, 0.94);
              border-radius: 6px;
              color: #111;
              overflow: hidden;
            }
            .mermaid svg, mjx-container svg {
              max-width: 100% !important;
              height: auto !important;
            }
            mjx-container {
              max-width: 100%;
              overflow: hidden !important;
            }
          </style>
          <script>
            window.MathJax = {
              tex: {
                inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
                displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
                processEscapes: true
              },
              svg: { fontCache: 'none' },
              options: { renderActions: { addMenu: [] } },
              startup: { typeset: false }
            };
          </script>
          <script src="https://cdn.jsdelivr.net/npm/marked@12/marked.min.js"></script>
          <script src="https://cdn.jsdelivr.net/npm/dompurify@3/dist/purify.min.js"></script>
          <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js"></script>
          <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        </head>
        <body>
          <div id="content"></div>
          <script>
            const source = \(markdownJSON);
            const content = document.getElementById('content');

            function escapeHTML(value) {
              return String(value || '').replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
            }

            function fallbackMarkdown(value) {
              let html = escapeHTML(value || ' ');
              html = html.replace(/^######\\s+(.+)$/gm, '<h6>$1</h6>');
              html = html.replace(/^#####\\s+(.+)$/gm, '<h5>$1</h5>');
              html = html.replace(/^####\\s+(.+)$/gm, '<h4>$1</h4>');
              html = html.replace(/^###\\s+(.+)$/gm, '<h3>$1</h3>');
              html = html.replace(/^##\\s+(.+)$/gm, '<h2>$1</h2>');
              html = html.replace(/^#\\s+(.+)$/gm, '<h1>$1</h1>');
              html = html.replace(/```([\\w-]*)\\n([\\s\\S]*?)```/g, '<pre><code>$2</code></pre>');
              html = html.replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>');
              html = html.replace(/__([^_]+)__/g, '<strong>$1</strong>');
              html = html.replace(/~~([^~]+)~~/g, '<del>$1</del>');
              html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
              html = html.replace(/\\n{2,}/g, '</p><p>');
              html = html.replace(/\\n/g, '<br>');
              return '<p>' + html + '</p>';
            }

            function reportHeight() {
              requestAnimationFrame(() => {
                const rect = content.getBoundingClientRect();
                const height = Math.max(24, Math.ceil(rect.height + 2));
                window.webkit.messageHandlers.height.postMessage(height);
              });
            }

            async function render() {
              try {
                if (window.marked) {
                  marked.setOptions({ gfm: true, breaks: true });
                  content.innerHTML = marked.parse(source || ' ');
                } else {
                  content.innerHTML = fallbackMarkdown(source || ' ');
                }

                if (window.DOMPurify) {
                  content.innerHTML = DOMPurify.sanitize(content.innerHTML, {
                    ADD_ATTR: ['target', 'class', 'checked', 'disabled'],
                    ADD_TAGS: ['input', 'svg', 'path', 'g', 'defs', 'marker', 'polygon', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'text', 'tspan', 'mjx-container']
                  });
                }

                content.querySelectorAll('pre code.language-mermaid, pre code.lang-mermaid').forEach((code) => {
                  const div = document.createElement('div');
                  div.className = 'mermaid';
                  div.textContent = code.textContent;
                  code.parentElement.replaceWith(div);
                });

                if (window.MathJax?.typesetPromise) {
                  await MathJax.typesetPromise([content]);
                }

                if (window.mermaid && content.querySelector('.mermaid')) {
                  mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'loose' });
                  await mermaid.run({ nodes: content.querySelectorAll('.mermaid') });
                }
              } catch (error) {
                content.innerHTML = fallbackMarkdown(source || ' ');
              } finally {
                document.documentElement.scrollTop = 0;
                document.body.scrollTop = 0;
                reportHeight();
                setTimeout(reportHeight, 150);
                setTimeout(reportHeight, 600);
                setTimeout(reportHeight, 1400);
              }
            }

            new ResizeObserver(reportHeight).observe(content);
            render();
          </script>
        </body>
        </html>
        """
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return string
    }

    private static func normalizedMarkdown(_ markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return markdown
        }

        var lines = trimmed.components(separatedBy: "\n")
        guard lines.count >= 1 else { return markdown }

        let openingFence = lines.removeFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        let language = openingFence
            .dropFirst(3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard isTopLevelMarkdownFenceLanguage(language) else {
            return markdown
        }

        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }

        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
            lines.removeLast()
        }

        return lines.joined(separator: "\n")
    }

    private static func isTopLevelMarkdownFenceLanguage(_ language: String) -> Bool {
        language.isEmpty ||
            language == "markdown" ||
            language == "md" ||
            language == "gfm" ||
            language == "text" ||
            language == "txt" ||
            language == "plain" ||
            language == "plaintext"
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat
        var markdown = ""

        init(height: Binding<CGFloat>) {
            _height = height
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MarkdownWebView.disableScrolling(in: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "height" else { return }

            if let value = message.body as? CGFloat {
                height = value
            } else if let value = message.body as? Double {
                height = CGFloat(value)
            } else if let value = message.body as? Int {
                height = CGFloat(value)
            }
        }
    }
}

private final class PassthroughWKWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
