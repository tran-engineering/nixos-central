# Shared home module: command-line development tooling. Opt in from a profile with
#   imports = [ ../../modules/home/dev-cli ];
# mise settings are defaults; a profile overrides one by setting the same option.
# git and jj are separate modules (git.nix, jj.nix).
{ pkgs, ... }:
{
  imports = [ ./environment.nix ];

  home.packages = with pkgs; [
    # Core
    ripgrep # fast recursive grep
    bfs # breadth-first find
    just # command runner
    jq # json query tool
    yq # yaml query tool
    sqlite
    gh # github cli
    lazygit
    nmap
    sops # encryption tool for secrets
    age # key generator for sops
    k6 # load testing

    # Languages
    rustup
    uv # python package manager
    pipenv
    pylint

    # AI coding agents
    unstable.claude-code
    unstable.opencode
    unstable.herdr # terminal multiplexer for agent harnesses

    # Infrastructure and cloud
    opentofu
    terraform
    terramate
    cmctl # needed in infra-terraform scripts
    tflint
    kubectl
    kubectx
    kubeseal
    kube-linter
    k9s
    kubernetes-helm
    argocd
    unstable.talosctl
    awscli2
    summon
    yamlfmt

    # Nix
    nixd
    nil
    nvd
    nh
    nix-tree
  ];
}
