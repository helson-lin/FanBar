cask "fanbar" do
  version "0.11.0"
  sha256 "fd7dc1829429c0bc9f1d56849e14d73495016404011ce930cbb1a8cce38f1107"

  url "https://github.com/helson-lin/FanBar/releases/download/v#{version}/FanBar-#{version}.dmg"
  name "FanBar"
  desc "Menu bar temperature monitor and fan controller"
  homepage "https://github.com/helson-lin/FanBar"

  auto_updates true
  depends_on :macos

  app "FanBar.app"
  binary "#{appdir}/FanBar.app/Contents/Helpers/fanbar"

  uninstall launchctl: ["local.fanbar.app", "local.fanbar.helper", "local.fanbar.helper.plist"],
            quit:      "local.fanbar.app",
            delete:    "~/Library/LaunchAgents/local.fanbar.app.plist"

  zap trash: [
    "~/Library/Caches/local.fanbar.app",
    "~/Library/Preferences/local.fanbar.app.plist",
    "~/Library/Saved Application State/local.fanbar.app.savedState",
  ]
end
