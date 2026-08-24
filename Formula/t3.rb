require "json"

class T3 < Formula
  desc "Agent harness control surface for coding agents"
  homepage "https://t3.codes/"
  url "https://registry.npmjs.org/t3/-/t3-0.0.33.tgz"
  sha256 "a60bf086e4a2de81b7d96ad25d6d11ff3701c555ce47d0246d0ef6ef578c8367"
  license "MIT"

  depends_on "node"
  depends_on "ripgrep"

  def install
    package_json = JSON.parse((buildpath/"package.json").read)
    package_json.delete("overrides")
    (buildpath/"package.json").atomic_write(JSON.pretty_generate(package_json))

    system "npm", "install", *std_npm_args

    node_modules = libexec/"lib/node_modules/t3/node_modules"
    node_pty_prebuilds = node_modules/"node-pty/prebuilds"

    if OS.mac?
      other_arch = Hardware::CPU.arm? ? "x64" : "arm64"
      rm_r node_pty_prebuilds/"darwin-#{other_arch}"
    elsif OS.linux?
      arch = Hardware::CPU.arm? ? "arm64" : "x64"
      claude_agent_sdk_musl = node_modules/"@anthropic-ai/claude-agent-sdk-linux-#{arch}-musl"
      msgpackr_extract = node_modules/"@msgpackr-extract/msgpackr-extract-linux-#{arch}"
      rm_r claude_agent_sdk_musl if claude_agent_sdk_musl.exist?
      rm_r msgpackr_extract if msgpackr_extract.exist?

      cd node_modules/"node-pty" do
        system "npm", "run", "install"
      end
    end

    generate_completions_from_executable(libexec/"bin/t3", "--completions")
    (bin/"t3").write_env_script libexec/"bin/t3", USE_BUILTIN_RIPGREP: "1"
  end

  service do
    run [opt_bin/"t3", "--no-browser", "--host", "127.0.0.1", "--port", "4141", "--base-dir", var/"t3"]
    keep_alive true
    working_dir var/"t3"
    log_path var/"log/t3.log"
    error_log_path var/"log/t3.log"
  end

  test do
    require "timeout"

    port = free_port
    read, write = IO.pipe
    pid = fork do
      read.close
      exec bin/"t3", "--no-browser", "--host", "127.0.0.1", "--port", port.to_s, out: write, err: write
    end
    write.close

    begin
      startup_output = +""
      Timeout.timeout(20) do
        until startup_output.include?("Listening on http://") && startup_output.include?(":#{port}")
          startup_output << read.readpartial(4096)
        end
      end

      assert_match "Listening on http://", startup_output
      assert_match ":#{port}", startup_output
      refute_empty shell_output("curl --fail --silent --retry 5 --retry-connrefused http://127.0.0.1:#{port}")
    ensure
      read.close
      Process.kill("TERM", pid)
      Process.wait(pid)
    end
  end
end
