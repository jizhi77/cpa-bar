cask "cpa-bar" do
  version "1.1.0"
  sha256 "f5a2bbb532ac4d4b8ae41bf184f4c45cc71b42476d27778b023205f1a4fbe6c3"

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
