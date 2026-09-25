class Docklayout < Formula
  desc "Save and switch macOS Dock layouts"
  homepage "https://github.com/nicolas-webdev/docklayout"
  url "https://github.com/nicolas-webdev/docklayout/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "afc25b693ae6d6d88ab50b1cebd7599f514d707f1e4908d193925ad47529d79a"
  license "MIT"

  depends_on :macos

  def install
    bin.install "bin/docklayout"
    zsh_completion.install "completions/zsh/_docklayout"
  end

  def caveats
    <<~EOS
      Save a layout with `docklayout save Work`.

      Raycast commands are written to ~/raycast-scripts.
      Add that folder in Raycast Settings → Extensions → Script Commands.
      Run `docklayout refresh` if the commands do not show up.
    EOS
  end

  test do
    assert_match "0.1.0", shell_output("#{bin}/docklayout --version")
  end
end
