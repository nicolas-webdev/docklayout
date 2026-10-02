class Docklayout < Formula
  desc "Save and switch macOS Dock layouts"
  homepage "https://github.com/nicolas-webdev/docklayout"
  url "https://github.com/nicolas-webdev/docklayout/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "cad6edd00a76594209b236bc9ffe6551fc9cbf16ff276a8484d6b0560b5806e2"
  license "MIT"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :ventura

  def install
    args = ["--disable-sandbox", "-c", "release", "--product", "docklayout"]
    system "swift", "build", *args
    # Newer SwiftPM builds into .build/out/…, older into .build/release; ask it.
    bin_path = Utils.safe_popen_read("swift", "build", *args, "--show-bin-path").chomp
    bin.install "#{bin_path}/docklayout"
    zsh_completion.install "completions/zsh/_docklayout"
  end

  def caveats
    <<~EOS
      This formula installs the terminal command only.
      The menu bar app is on the releases page:
        https://github.com/nicolas-webdev/docklayout/releases
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/docklayout --version")
  end
end
