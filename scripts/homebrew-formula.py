#!/usr/bin/env python3
"""Generate a formula for the built artifact; use --url for a published release URL."""
import argparse, hashlib, pathlib, urllib.parse
parser = argparse.ArgumentParser()
parser.add_argument('--url')
parser.add_argument('--output', default='dist/uvm.rb')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
archive = root / 'dist/uVirtualization-0.1.0-dev-macos-arm64.zip'
url = args.url or archive.as_uri()
assert urllib.parse.urlparse(url).scheme in ('https', 'file'), 'Use HTTPS or a local development file'
assert all(c not in url for c in ['"', '\n', '\r', '#', '\\']), 'Invalid URL'
hash = hashlib.sha256(archive.read_bytes()).hexdigest()
formula = f'''class Uvm < Formula
  desc "Swift virtual machine manager for Apple silicon"
  homepage "https://github.com/muzammilpeer/uVirtualization"
  url "{url}"
  version "0.1.0-dev"
  sha256 "{hash}"
  depends_on arch: :arm64
  depends_on macos: :ventura

  def install
    libexec.install "uVirtualization.app"
    bin.install_symlink libexec/"uVirtualization.app/Contents/MacOS/uvm"
    bin.install_symlink libexec/"uVirtualization.app/Contents/MacOS/gitlab-uvm-executor"
  end

  test do
    assert_match "uvm", shell_output("#{{bin}}/uvm --version")
  end
end
'''
output = root / args.output
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(formula)
print(output)
