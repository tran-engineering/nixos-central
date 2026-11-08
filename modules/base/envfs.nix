# Conventional executable paths on every machine: /usr/bin/<name> and
# /bin/<name> resolve to <name> on the PATH of the process that asks, so
# `#!/bin/bash`, `#!/usr/bin/python3` or a hard-coded /usr/bin/git in scripts
# from other distributions work. envfs mounts a FUSE filesystem on /usr/bin
# and bind-mounts it on /bin.
#
# The result depends on the caller's PATH: a program from a user's profile or
# a `nix shell` is visible to that user only, not to root or services. Names
# in the fallback directory resolve without PATH: sh and env (from the NixOS
# module, replacing its /bin/sh and /usr/bin/env activation scripts) and bash,
# the interpreter scripts hard-code most often.
{ pkgs, ... }:
{
  services.envfs = {
    enable = true;
    extraFallbackPathCommands = ''
      ln -s ${pkgs.bashInteractive}/bin/bash $out/bash
    '';
  };
}
