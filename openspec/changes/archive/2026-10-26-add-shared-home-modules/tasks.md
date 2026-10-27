# Tasks

## 1. general-tools module

- [x] 1.1 Add `modules/home/general-tools.nix` with aria2, yt-dlp, p7zip, bat, mc, dust, ncdu, rsync, ffmpeg, imagemagick, exiftool, poppler-utils, whois, dnsutils, qrencode, eza, iftop (header comment: what it is, how to import it); verify with `nix eval --json .#lib.profileNames` that the profile list is unchanged (`["_default"]`)

## 2. dev-cli module

- [x] 2.1 Add `modules/home/dev-cli/default.nix` with the packages grouped by comment: core (ripgrep, bfs, just, jq, yq, sqlite, gh, lazygit, nmap, sops, age, k6), languages (rustup, uv, pipenv, pylint), AI agents (`unstable.claude-code`, `unstable.opencode`, `unstable.herdr`), infra/cloud (opentofu, terraform, terramate, kubectl, kubectx, kubeseal, kube-linter, k9s, tflint, argocd, summon, awscli2, kubernetes-helm, `unstable.talosctl`, yamlfmt), nix (nixd, nil, nvd, nh, nix-tree); imports `./environment.nix` and `./vcs.nix`
- [x] 2.2 Add `modules/home/dev-cli/environment.nix`: `~/.cargo/bin` and `~/.local/share/pnpm/bin` in `home.sessionPath`, `PNPM_HOME` in `home.sessionVariables`, `programs.mise.enable` with global `tools.node = [ "24" ]` and `settings.all_compile = false` as per-leaf `lib.mkDefault`
- [x] 2.3 Add `modules/home/git.nix` and `modules/home/jj.nix` (jj with jjui; originally `dev-cli/vcs.nix`, split out as opt-in modules): `programs.git.enable`/`programs.jujutsu.enable`, and as per-leaf `lib.mkDefault` the git settings `push.autoSetupRemote`, `pull.rebase`, `rebase.autoStash`, `lfs.enable` and the jj settings `remotes.origin.auto-track-bookmarks`, `remotes.origin.auto-track-created-bookmarks`, `git.private-commits`, `snapshot.max-new-file-size`; no names or emails
- [x] 2.4 Verify the module standalone and the override rule: `nix build --impure --expr` of `lib.mkHome` with a scratch profile that imports only `dev-cli` and sets `programs.git.settings.pull.rebase = false` and `programs.jujutsu.settings.user.name = "x"`. Confirm it builds, the generated git config has `rebase = false`, and the jj config still contains `auto-track-bookmarks` and `private-commits`. Do not commit the scratch.

## 3. dev-desktop module

- [x] 3.1 Add `modules/home/dev-desktop.nix`: `programs.zed-editor` with `package = pkgs.unstable.zed-editor` and no user settings, `home.shellAliases.zed = "zeditor"`, and `unstable.claude-agent-acp`; add `idea.nix`, `godot.nix` (`unstable.godot`), `drawio.nix` as separate modules; no GPU tools, no custom desktop entries
- [x] 3.2 Verify the built home contains `share/applications/dev.zed.Zed.desktop` (`ls <home-path>/home-path/share/applications`) and desktop files for IDEA, Godot and draw.io

## 4. kt profile and CI coverage

- [x] 4.1 Add `users/kt/default.nix` importing `../_default`, `../../modules/home/general-tools.nix`, `../../modules/home/dev-cli` and `../../modules/home/dev-desktop.nix`, with a comment that personal settings follow; verify `nix eval --json .#lib.profileNames` returns `["_default","kt"]`
- [x] 4.2 In `flake.nix`, switch the `home-profile-<name>` checks to eval-only (`writeText` of `activationPackage.drvPath`, as in `home-eval-*`), add `homeConfigurations.ci-home-kt-aarch64` (`ciHome { system = "aarch64-linux"; profile = "kt"; }`), and add an eval-only check `host-eval-kt` for `ciHost "ci-kt" { desktop = "none"; user = "kt"; }` in `checks` (not in `nixosConfigurations`); verify `nix flake check` passes, and that `nix build .#checks.x86_64-linux.home-profile-kt --dry-run` lists no store paths to fetch beyond the check's own text file
- [x] 4.3 One-time local check, not in CI: `nix build` the `kt` profile's activation package, then verify there are no collision errors and that `rg`, `jj`, `kubectl`, `claude`, `nixd`, `eza`, `zeditor` exist in `home-path/bin` and `mise` is configured with Node.js 24
- [x] 4.4 Update `README.md`: a "Shared modules" subsection under "Users and profiles" (the three modules, what each provides, the import lines, that git/jj/mise defaults can be overridden by setting the same option, that modules carry no identity). In "Development", replace "every selectable profile is also built standalone" with "evaluated", and add `ci-home-kt-aarch64` to the sample homes. Verify the documented import lines match `users/kt/default.nix`.

## 5. Login shell selection

- [x] 5.1 Add `modules/home/shell.nix` (option `nixos-central.shell`, enum bash/fish/zsh, default bash; enables `programs.<shell>.enable`) and include it in every profile: `home-manager.sharedModules` in `modules/user.nix` and the module list of `lib.mkHome`; verify `nix eval` of `ci-home-default`'s `config.nixos-central.shell` is `"bash"` and that `host-ci-kde`'s toplevel drvPath is unchanged
- [x] 5.2 In `modules/user.nix`, for fish/zsh set `users.users.<user>.shell` and system `programs.<shell>.enable` from the profile's option; verify with `nix eval` on a scratch `mkHost` whose user's profile selects zsh (without the zsh module) that `users.users.<user>.shell` is zsh and the toplevel evaluates
- [x] 5.3 Change `shell_hint` in `home-only.sh` to evaluate the selected shell from the local flake and hint only for it (no hint for bash or when it is already the login shell); verify with shellcheck and the existing home-installer VM tests via `nix flake check`

## 6. Shell and terminal modules

- [x] 6.1 Add `modules/home/fish/` (`default.nix`, `tide.fish` from k-nixos): fish, plugins tide/fzf-fish/z/fish-cd-gitroot, `fzf` and `fd`, tide config in `conf.d` with `mkDefault` source, `nerd-fonts.symbols-only` + `fonts.fontconfig.enable`; verify a local build of a scratch home has `fish/conf.d/tide.fish` and `fish -c 'functions -q fish_prompt'` succeeds with the built config
- [x] 6.2 Add `modules/home/zsh.nix` (completion, autosuggestion, syntax highlighting, history); verify the built `.zshrc` sources both plugins
- [x] 6.3 Add `modules/home/foot.nix` and `modules/home/ghostty.nix` with per-leaf `mkDefault` defaults (foot also installs the symbols font); verify the built `foot.ini` / ghostty `config` contain the defaults and that a scratch override of ghostty `font-size` wins
- [x] 6.4 In `users/kt`: import fish, zsh, foot, ghostty; select fish; add the personal terminal look (FantasqueSansM Nerd Font, foot kitty theme and `term`, ghostty `dankcolors` theme and font) and `ls = eza`; verify `host-eval-kt` evaluates with `users.users.kt.shell` = fish, and a local build of the profile succeeds without collisions
- [x] 6.5 Update `README.md`: the new modules in the "Shared modules" table, and a short "Login shell" part (`nixos-central.shell`, NixOS applies it, standalone prints the `chsh` command); verify the documented option name and values match `shell.nix`

## Workflow follow-up

- After merge, check the next daily flake-update PR still passes with the `unstable` packages in the modules.
- A later change fills `users/kt` with personal settings (identity, fish/tide, ai-agent, personal GUI apps).
