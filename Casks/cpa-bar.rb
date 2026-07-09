cask "cpa-bar" do
  version "1.0.2"
  sha256 "0c57a784adbb4c9ff9602c79cb3256d7a13c4e29ce4308ee9a0c419fc3d62141"

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
