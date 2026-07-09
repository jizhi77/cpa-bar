cask "cpa-bar" do
  version "1.0.2"
  sha256 "f70d461f63a5457c93dd3c1ee0b46e8e76176c935ea042986ff794acc3ca4946"

  url "https://github.com/jizhi77/cpa-bar/releases/download/v#{version}/CPAQuotaBar.zip"
  name "CPAQuotaBar"
  desc "Menu bar utility for viewing CPA Codex quotas"
  homepage "https://github.com/jizhi77/cpa-bar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "CPAQuotaBar.app"

  zap trash: "~/Library/Preferences/com.cpa-bar.CPAQuotaBar.plist"
end
