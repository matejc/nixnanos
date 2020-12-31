# NixNanos

NixNanos is a NixOS module for [NanoVMS](https://nanovms.com/) for completely declarative configuration of VMs.
It is using [OPS](https://nanovms.gitbook.io/ops/) in its core.
Every VM is managed as a separate SystemD service.


## Examples

This belongs into /etc/nixos/configuration.nix

```nix
  imports =
    [
      ...
      <your path to nixnanos repository>/module.nix
    ];

  services.nanos = {
    enable = true;

    vms.hello_world =
      let
        hello_world_src = builtins.fetchurl {
          url = https://raw.githubusercontent.com/nanovms/ops-examples/master/nodejs/03-hello-world-http/hi.js;
        };
      in {
        # Get all package names by running `ops pkg list`
        packagename = "node_v14.2.0";
        # Explanation of config options: https://nanovms.gitbook.io/ops/configuration
        configuration = {
          Files = [ "${hello_world_src}" ];
          Args = [ "${hello_world_src}" ];
          RunConfig.Ports = [ "8083" ];
        };
      };

    vms.ssh_chat =
      let
        ssh_chat = pkgs.runCommand "ssh-chat" {
          src = pkgs.fetchurl {
            url = https://github.com/shazow/ssh-chat/releases/download/v1.10/ssh-chat-linux_amd64.tgz;
            sha256 = "08k54dsdsx4k38fif90bn86979jf85dfsrqva5bawzk976394nx0";
          };
          buildInputs = [ pkgs.gnutar pkgs.gzip ];
        } ''
          tar xzf $src
          mv ssh-chat/ssh-chat $out
        '';
        ssh_keys = pkgs.runCommand "ssh-keys" {
          buildInputs = [ pkgs.openssh ];
        } ''
          mkdir -p $out
          ssh-keygen -b 2048 -t rsa -f $out/id_rsa -q -N ""
        '';
      in {
        # You can also run ELF binaries directly
        elf = ssh_chat;
        configuration = {
          Args = [ "${ssh_chat}" "-i" "${ssh_keys}/id_rsa" ];
          Files = [
            "${ssh_keys}/id_rsa"
          ];
          RunConfig.Ports = [ "2022" ];
        };
      };
  };

  ...
```
