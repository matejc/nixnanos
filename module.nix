{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nanos;

  manifestSrc = builtins.fetchurl {
    url = "https://storage.googleapis.com/packagehub/manifest.json";
  };
  manifest = builtins.fromJSON (builtins.readFile manifestSrc);

  vmOpts = {config, lib, name, ... }:
  {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };
      packagename = mkOption {
        type = types.nullOr (types.enum (attrNames manifest));
        default = null;
        description = "List packages by running `ops pkg list`.";
      };
      configuration = mkOption {
        type = types.attrs;
        description = "VM config, will be passed as JSON to OPS (https://nanovms.gitbook.io/ops/configuration)";
        default = {};
      };
    };
  };

  mkPackagesDir =
    let
      vms = filterAttrs (n: v: v.packagename != null) cfg.vms;
      packages = map (v: {
        name = v.packagename;
        value = fetchurl {
          url = "https://storage.googleapis.com/packagehub/${v.packagename}.tar.gz";
          sha256 = manifest."${v.packagename}".sha256;
        };
      }) (attrValues vms);
    in
      pkgs.runCommand "packages" {} ''
        mkdir -p $out
        ln -s "${manifestSrc}" "$out/manifest.json"

        ${concatMapStringsSep "\n" (v: ''
          ln -s "${v.value}" "$out/${v.packagename}.tar.gz"
        '') packages}
      '';

  services = mapAttrsToList (n: v:
    let
      configFile = builtins.toFile "config.json" (builtins.toJSON v.configuration);
    in setAttrByPath ["systemd" "services" "nanos-${n}"] {
      description = "NanosVMS ${n} (${v.packagename})";
      serviceConfig = {
        Type = "simple";
        User = "nanos";
        Group = "nanos";
        # mixed - first send SIGINT to main process,
        # then after 2min send SIGKILL to whole group if neccessary
        KillMode = "mixed";
        KillSignal = "SIGINT";
        TimeoutSec = 60;  # wait 1min untill SIGKILL
        ExecStart = "${cfg.ops.package}/bin/ops load ${v.packagename} -c ${configFile}";
      };
    }
  ) cfg.vms;
in
{
  options = {
    services.nanos = {
      enable = mkEnableOption "Enable NanoVMS";

      ops.package = mkOption {
        type = types.package;
        default = pkgs.callPackage ./ops { };
        description = "OPS package";
      };

      vms = mkOption {
        type = types.attrsOf (types.submodule vmOpts);
        description = ''
          Nanos virtual machine configurations.
        '';
        default = {};
      };
    };
  };

  config = mkIf cfg.enable (recursiveUpdate {
    environment.systemPackages = [ cfg.ops.package ];

    users.users.nanos = {
      description = "NanoVMS runner user";
      group = "nanos";
      isSystemUser = true;
      home = "/var/lib/nanos";
      createHome = true;
    };

    users.groups.nanos = { };

    system.activationScripts.nanos-init.text = ''
      mkdir -p /var/lib/nanos/.ops
      rm -f /var/lib/nanos/.ops/packages
      ln -s "${mkPackagesDir}" "/var/lib/nanos/.ops/packages"
    '';
  } services);
}
