# Tasks

## 1. plasma-manager

- [x] 1.1 Add the `plasma-manager` input (following `nixpkgs` and `home-manager`) and lock it; add `plasma-manager.homeModules.plasma-manager` to `home-manager.sharedModules` and to `lib.mkHome`'s modules; verify the sample hosts' and homes' activation packages are unchanged when no profile sets `programs.plasma`
- [x] 1.2 Set a Plasma option in `users/ci-modules`; verify `host-eval-ci-modules`, `home-eval-ci-modules` and `home-eval-ci-home-modules-aarch64` evaluate and the Plasma activation step (plasma-manager writes KDE config at activation, not as files) contains it

## 2. logseq

- [x] 2.1 Permit `electron-39.8.10` in `nixos-central-internal/lib/nixpkgs.nix` with a comment on why and when to remove it; verify `pkgs.unstable.logseq` evaluates for a standalone home and a NixOS user, and that another insecure package still fails

## 3. Documentation

- [x] 3.1 README: mention `programs.plasma` (plasma-manager) and the logseq exception in "Users and profiles"; verify `nix flake check` passes
