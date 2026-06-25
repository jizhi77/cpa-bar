cask "cpa-bar" do
  version "1.0.0"
  sha256 "6272c33bf025e8615de626e9017d339952a47ebca80ed9719fae9a9eef981982"

  url "https://github.com/jizhi77/cpa-bar/releases/download/v#{version}/CPAQuotaBar.zip"
  name "CPAQuotaBar"
  desc "Menu bar utility for viewing CPA Codex quotas"
  homepage "https://github.com/jizhi77/cpa-bar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "CPAQuotaBar.app"

  zap trash: "~/Library/Preferences/com.cpa-bar.CPAQuotaBar.plist"
end
