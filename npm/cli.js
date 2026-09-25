#!/usr/bin/env node
"use strict";

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const root = path.resolve(__dirname, "..");
const pythonCli = path.join(root, "bin", "docklayout");
const appSource = path.join(root, "app", "DockLayout.app");
const agentLabel = "com.nicolaswebdev.docklayout";

function forward(args) {
  const result = spawnSync(pythonCli, args, { stdio: "inherit" });
  process.exit(result.status === null ? 1 : result.status);
}

function xmlEscape(value) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function install() {
  if (process.platform !== "darwin") {
    console.error("docklayout only works on macOS.");
    process.exit(1);
  }
  if (!fs.existsSync(appSource)) {
    console.error("Menu bar app is missing from this package. Rebuild with scripts/build-app.sh.");
    process.exit(1);
  }
  if (process.arch !== "arm64") {
    console.error("The menu bar app is built for Apple silicon.");
    process.exit(1);
  }

  const home = os.homedir();
  const support = path.join(home, "Library", "Application Support", "docklayout");
  const appDest = path.join(support, "DockLayout.app");
  const cliDest = path.join(support, "docklayout");
  const binDir = path.join(home, ".local", "bin");
  const binLink = path.join(binDir, "docklayout");
  const agentDir = path.join(home, "Library", "LaunchAgents");
  const agentPath = path.join(agentDir, `${agentLabel}.plist`);
  const executable = path.join(appDest, "Contents", "MacOS", "docklayout-bar");

  fs.mkdirSync(support, { recursive: true });
  fs.mkdirSync(binDir, { recursive: true });
  fs.mkdirSync(agentDir, { recursive: true });
  fs.copyFileSync(pythonCli, cliDest);
  fs.chmodSync(cliDest, 0o755);
  fs.rmSync(appDest, { recursive: true, force: true });
  fs.cpSync(appSource, appDest, { recursive: true });
  fs.chmodSync(executable, 0o755);

  try {
    fs.lstatSync(binLink);
    fs.unlinkSync(binLink);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  fs.symlinkSync(cliDest, binLink);

  const completionDir = path.join(home, ".config", "docklayout", "zsh");
  fs.mkdirSync(completionDir, { recursive: true });
  fs.copyFileSync(
    path.join(root, "completions", "zsh", "_docklayout"),
    path.join(completionDir, "_docklayout")
  );
  const zshrc = path.join(home, ".zshrc");
  const marker = "docklayout/zsh";
  const existing = fs.existsSync(zshrc) ? fs.readFileSync(zshrc, "utf8") : "";
  if (!existing.includes(marker)) {
    fs.appendFileSync(
      zshrc,
      "\n# docklayout tab completion\nfpath=(~/.config/docklayout/zsh $fpath)\nautoload -Uz compinit && compinit -C\n"
    );
  }

  const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${agentLabel}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${xmlEscape(executable)}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>DOCKLAYOUT_BIN</key>
    <string>${xmlEscape(cliDest)}</string>
  </dict>
</dict>
</plist>
`;
  fs.writeFileSync(agentPath, plist);

  const domain = `gui/${process.getuid()}`;
  spawnSync("launchctl", ["bootout", `${domain}/${agentLabel}`], { stdio: "ignore" });
  const boot = spawnSync("launchctl", ["bootstrap", domain, agentPath], { stdio: "inherit" });
  if (boot.status !== 0) {
    const loaded = spawnSync("launchctl", ["load", "-w", agentPath], { stdio: "inherit" });
    if (loaded.status !== 0) {
      console.error("Installed the files, but the menu bar app did not start.");
      console.error(`Open it with: open "${appDest}"`);
      process.exit(loaded.status === null ? 1 : loaded.status);
    }
  }

  console.log("Dock Layout is in the menu bar.");
  console.log("Click the dock icon to switch, or to save the Dock you have now.");
  console.log("It starts again when you log in. Quit Dock Layout leaves it off until then.");
  console.log("");
  console.log("Terminal:");
  console.log("  docklayout save Work");
  console.log("  docklayout load Work");
}

function uninstall() {
  const home = os.homedir();
  const domain = `gui/${process.getuid()}`;
  spawnSync("launchctl", ["bootout", `${domain}/${agentLabel}`], { stdio: "ignore" });
  fs.rmSync(path.join(home, "Library", "LaunchAgents", `${agentLabel}.plist`), { force: true });
  fs.rmSync(path.join(home, "Library", "Application Support", "docklayout"), {
    recursive: true,
    force: true,
  });
  const binLink = path.join(home, ".local", "bin", "docklayout");
  try {
    fs.lstatSync(binLink);
    fs.unlinkSync(binLink);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  fs.rmSync(path.join(home, ".config", "docklayout", "zsh", "_docklayout"), { force: true });
  console.log("Removed Dock Layout.");
  console.log("Saved layouts are still in ~/.config/docklayout/layouts");
}

const args = process.argv.slice(2);
if (args[0] === "uninstall") {
  uninstall();
} else if (args.length > 0) {
  forward(args);
} else {
  install();
}
