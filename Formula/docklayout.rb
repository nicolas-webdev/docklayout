class Docklayout < Formula
  desc "Save and switch macOS Dock layouts"
  homepage "https://github.com/nicolas-webdev/docklayout"
  url "https://github.com/nicolas-webdev/docklayout/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "8cebd9e349c3b8804c53c44d21a8dd740f63726a47a34372e17a03d589adfd43"
  license "MIT"

  depends_on :macos

  def install
    bin.install "bin/docklayout"
    zsh_completion.install "completions/zsh/_docklayout"
  end

  def caveats
    <<~EOS
      This formula installs the terminal command only.

      The menu bar app, for Apple silicon, is:
        npx github:nicolas-webdev/docklayout
    EOS
  end

  test do
    assert_match "0.2.0", shell_output("#{bin}/docklayout --version")
  end
end
