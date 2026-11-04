/** What a person sees opening https://update.getfanbar.com in a browser. Static, no tracking. */
const PAGE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>FanBar update service</title>
<style>
  :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  body { max-width: 36rem; margin: 4rem auto; padding: 0 1.5rem; line-height: 1.6; }
  h1 { font-size: 1.4rem; margin-bottom: 0.5rem; }
  p { margin: 0.75rem 0; }
  ul { padding-left: 1.2rem; }
  code { font-size: 0.9em; }
</style>
</head>
<body>
<h1>FanBar update service</h1>
<p>This address is FanBar's update feed. The app's update check requests <code>/appcast.xml</code>, which redirects to the appcast on GitHub and is counted anonymously: by default only the app version per day; Mac model, macOS version, chip and country only if you opt in. No IP address or device ID is stored, and groups smaller than 5 are never published.</p>
<p lang="zh-Hans">这是 FanBar 的更新源。应用检查更新时请求 <code>/appcast.xml</code>，它会跳转到 GitHub 上的 appcast，并做匿名计数：默认只按天统计应用版本；只有开启统计后才包含 Mac 型号、macOS 版本、芯片和国家。不保存 IP 地址或设备 ID，少于 5 的分组不会公开。</p>
<ul>
  <li><a href="/api/stats">Aggregate statistics (JSON) / 汇总统计</a></li>
  <li><a href="https://github.com/helson-lin/FanBar/tree/main/services/update">Source code / 源码</a></li>
  <li><a href="https://getfanbar.com">getfanbar.com</a></li>
</ul>
</body>
</html>
`;

export function home() {
  return new Response(PAGE, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=86400',
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'",
      'X-Content-Type-Options': 'nosniff',
    },
  });
}
