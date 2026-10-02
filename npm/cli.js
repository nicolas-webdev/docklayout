#!/usr/bin/env node
"use strict";

// npx github:nicolas-webdev/docklayout              install (or update) the app
// npx github:nicolas-webdev/docklayout uninstall    remove it
// npx github:nicolas-webdev/docklayout <command>    run the docklayout command
//
// Installs the same native app as the DMG on the releases page, downloaded
// from the latest GitHub release.

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const repo = "nicolas-webdev/docklayout";
const appName = "Dock Layout.app";
const home = os.homedir();
const appDirs = ["/Applications", path.join(home, "Applications")];
const binLink = path.join(home, ".local", "bin", "docklayout");
const completionDir = path.join(home, ".config", "docklayout", "zsh");

function fail(message) {
  console.error(message);
  process.exit(1);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: "inherit", ...options });
  if (result.status !== 0) {
    fail(`${command} ${args.join(" ")} failed.`);
  }
  return result;
}

function installedApp() {
  return appDirs.map((dir) => path.join(dir, appName)).find((app) => fs.existsSync(app));
}

function helper(app) {
  return path.join(app, "Contents", "Helpers", "docklayout");
}

function checkMac() {
  if (process.platform !== "darwin") {
    fail("docklayout only works on macOS.");
  }
  // Darwin 22 is macOS 13.
  if (parseInt(os.release(), 10) < 22) {
    fail("Dock Layout needs macOS 13 or newer.");
  }
}

function isSymlink(file) {
  try {
    return fs.lstatSync(file).isSymbolicLink();
  } catch {
    return false;
  }
}

async function latestDmg() {
  const response = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
    headers: { Accept: "application/vnd.github+json", "User-Agent": "docklayout-installer" },
  });
  if (!response.ok) {
    fail(`Couldn't look up the latest release (HTTP ${response.status}).`);
  }
  const release = await response.json();
  const asset = (release.assets || []).find((item) => item.name.endsWith(".dmg"));
  if (!asset) {
    fail(`The latest release (${release.tag_name}) has no DMG yet. Try again in a few minutes.`);
  }
  return { version: release.tag_name, name: asset.name, url: asset.browser_download_url };
}

async function download(url, file) {
  const response = await fetch(url, { headers: { "User-Agent": "docklayout-installer" } });
  if (!response.ok) {
    fail(`Download failed (HTTP ${response.status}).`);
  }
  fs.writeFileSync(file, Buffer.from(await response.arrayBuffer()));
}

function destination() {
  const existing = installedApp();
  if (existing) {
    return path.dirname(existing);
  }
  try {
    fs.accessSync("/Applications", fs.constants.W_OK);
    return "/Applications";
  } catch {
    return appDirs[1];
  }
}

function linkCommand(app) {
  fs.mkdirSync(path.dirname(binLink), { recursive: true });
  if (isSymlink(binLink)) {
    fs.unlinkSync(binLink);
  } else if (fs.existsSync(binLink)) {
    console.warn(`Left ${binLink} alone: it isn't a link this installer made.`);
    return;
  }
  fs.symlinkSync(helper(app), binLink);
}

function installCompletion(app) {
  fs.mkdirSync(completionDir, { recursive: true });
  fs.copyFileSync(
    path.join(app, "Contents", "Resources", "completions", "_docklayout"),
    path.join(completionDir, "_docklayout")
  );
  const zshrc = path.join(home, ".zshrc");
  const existing = fs.existsSync(zshrc) ? fs.readFileSync(zshrc, "utf8") : "";
  if (!existing.includes("docklayout/zsh")) {
    fs.appendFileSync(
      zshrc,
      "\n# docklayout tab completion\nfpath=(~/.config/docklayout/zsh $fpath)\nautoload -Uz compinit && compinit -C\n"
    );
  }
}

async function install() {
  checkMac();
  const release = await latestDmg();
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "docklayout-"));
  const dmg = path.join(tmp, release.name);
  const mount = path.join(tmp, "mount");

  console.log(`Downloading Dock Layout ${release.version}…`);
  await download(release.url, dmg);

  fs.mkdirSync(mount);
  run("hdiutil", ["attach", dmg, "-nobrowse", "-readonly", "-noautoopen", "-quiet", "-mountpoint", mount]);
  const dir = destination();
  const app = path.join(dir, appName);
  try {
    // Quit a running copy so it can be replaced; ignore "not running".
    spawnSync("pkill", ["-x", "DockLayout"]);
    fs.mkdirSync(dir, { recursive: true });
    fs.rmSync(app, { recursive: true, force: true });
    // ditto keeps the bundle's code signature intact.
    run("ditto", [path.join(mount, appName), app]);
  } finally {
    spawnSync("hdiutil", ["detach", mount, "-quiet"]);
    fs.rmSync(tmp, { recursive: true, force: true });
  }

  linkCommand(app);
  installCompletion(app);
  // On first launch the app turns on Start at Login and cleans up the
  // pre-0.3 npx install (its login agent and Python script).
  run("open", [app]);

  console.log(`Dock Layout is in the menu bar (installed in ${dir}).`);
  console.log("Click the dock icon to switch, or to save the Dock you have now.");
  console.log("");
  console.log("Terminal:");
  console.log("  docklayout save Work");
  console.log("  docklayout load Work");
}

function uninstall() {
  spawnSync("pkill", ["-x", "DockLayout"]);
  spawnSync("pkill", ["-x", "docklayout-bar"]);
  for (const dir of appDirs) {
    fs.rmSync(path.join(dir, appName), { recursive: true, force: true });
  }
  if (isSymlink(binLink)) {
    fs.unlinkSync(binLink);
  }
  fs.rmSync(path.join(completionDir, "_docklayout"), { force: true });

  // Left behind by the pre-0.3 npx install.
  const label = "com.nicolaswebdev.docklayout";
  spawnSync("launchctl", ["bootout", `gui/${process.getuid()}/${label}`], { stdio: "ignore" });
  fs.rmSync(path.join(home, "Library", "LaunchAgents", `${label}.plist`), { force: true });
  fs.rmSync(path.join(home, "Library", "Application Support", "docklayout"), {
    recursive: true,
    force: true,
  });

  console.log("Removed Dock Layout.");
  console.log("Saved layouts are still in ~/.config/docklayout/layouts");
}

function forward(args) {
  checkMac();
  const app = installedApp();
  if (!app) {
    fail("Dock Layout isn't installed. Install it with: npx github:nicolas-webdev/docklayout");
  }
  const result = spawnSync(helper(app), args, { stdio: "inherit" });
  process.exit(result.status === null ? 1 : result.status);
}

const args = process.argv.slice(2);
if (args[0] === "uninstall") {
  uninstall();
} else if (args.length > 0) {
  forward(args);
} else {
  install().catch((error) => fail(error.message));
}
