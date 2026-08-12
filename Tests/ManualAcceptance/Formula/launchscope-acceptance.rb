class LaunchscopeAcceptance < Formula
  desc "Disposable service fixture for LaunchScope release acceptance"
  homepage "https://github.com/nekutai/launchscope"
  url "file:///tmp/launchscope-acceptance-worker.sh"
  sha256 "932ef9cd8f9c45c5e6744ca740b87618bd7101c8889c98dfc30aba4a39579a50"
  version "0.1.0"

  def install
    bin.install "launchscope-acceptance-worker.sh" => "launchscope-acceptance"
  end

  service do
    run [opt_bin/"launchscope-acceptance", "--service"]
    keep_alive false
    log_path var/"log/launchscope-acceptance.log"
    error_log_path var/"log/launchscope-acceptance.log"
  end

  test do
    system bin/"launchscope-acceptance", "--once"
  end
end
