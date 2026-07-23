cask "cpa-bar" do
  version "1.0.2"
  sha256 "feef2c557e85316cc9e035d146d720bce19b89900d925671d33e46881b9bd905"

  url "https://github.com/jizhi77/cpa-bar/releases/download/v#{version}/CPAQuotaBar.zip"
  name "CPAQuotaBar"
  desc "Menu bar utility for viewing CPA Codex and xAI quotas"
  homepage "https://github.com/jizhi77/cpa-bar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "CPAQuotaBar.app"

  zap trash: "~/Library/Preferences/com.cpa-bar.CPAQuotaBar.plist"
end
