cask "consai" do
  version "0.1.0"
  # Update sha256 after each release:
  #   curl -L https://github.com/DonsWayo/consai/releases/download/v#{version}/Consai-#{version}.dmg | shasum -a 256
  sha256 "REPLACE_WITH_SHA256_OF_DMG"

  url "https://github.com/DonsWayo/consai/releases/download/v#{version}/Consai-#{version}.dmg"
  name "Consai"
  desc "Menu-bar-first macOS companion for Apple's container tooling"
  homepage "https://github.com/DonsWayo/consai"

  depends_on macos: ">= :sequoia"

  app "Consai.app"

  zap trash: [
    "~/Library/Application Support/com.donswayo.consai",
    "~/Library/Preferences/com.donswayo.consai.plist",
    "~/Library/Caches/com.donswayo.consai",
  ]
end
