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
      elf = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Elf executable.";
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
        value = pkgs.fetchurl {
          url = "https://storage.googleapis.com/packagehub/${v.packagename}.tar.gz";
          sha256 = manifest."${v.packagename}".sha256;
        };
      }) (attrValues vms);
    in
      pkgs.runCommand "packages" {} ''
        mkdir -p $out
        ln -s "${manifestSrc}" "$out/manifest.json"

        ${concatMapStringsSep "\n" (v: ''
          ln -s "${v.value}" "$out/${v.name}.tar.gz"
        '') packages}
      '';

  mkReleaseDir =
    let
      nanosSrc = builtins.fetchurl {
        url = "https://storage.googleapis.com/nanos/release/${cfg.version}/nanos-release-linux-${cfg.version}.tar.gz";
      };
    in
      pkgs.runCommand "${cfg.version}" {
        buildInputs = with pkgs; [ gnutar gzip patchelf ];
      } ''
        mkdir -p $out
        tar xzf "${nanosSrc}" -C $out/
        patchelf --set-interpreter "${pkgs.stdenv.cc.libc}/lib/ld-linux-x86-64.so.2" \
          $out/mkfs
      '';

  services = mapAttrs' (n: v:
    let
      vmConfig = {
        Boot = "/var/lib/nanos/.ops/${cfg.version}/boot.img";
        Kernel = "/var/lib/nanos/.ops/${cfg.version}/kernel.img";
        Mkfs = "/var/lib/nanos/.ops/${cfg.version}/mkfs";
      } // v.configuration;
      configFile = pkgs.writeText "config.json" (builtins.toJSON vmConfig);
      args =
        assert asserts.assertMsg ((v.packagename != null) != (v.elf != null)) "Only one, elf or packagename can be defined";
        if v.packagename == null then
          "run ${v.elf}"
        else
          "load ${v.packagename}";
    in nameValuePair "nanos-${n}" {
      description = "NanosVMS ${n}";
      after = [ "nanos-bridge-net.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "nanos";
        Group = "nanos";
        # mixed - first send SIGINT to main process,
        # then after 1min send SIGKILL to whole group if neccessary
        KillMode = "mixed";
        KillSignal = "SIGINT";
        TimeoutSec = 60;  # wait 1min untill SIGKILL
        ExecStart = "${cfg.ops.package}/bin/ops ${args} -c ${configFile}";
        Restart = "always";
        RestartSec = 1;
      };
      startLimitIntervalSec = 10;
      startLimitBurst = 5;
      path = [ config.virtualisation.libvirtd.qemuPackage ];
    }
  ) cfg.vms;
in
{
  options = {
    services.nanos = {
      enable = mkEnableOption "Enable NanoVMS";

      version = mkOption {
        type = types.str;
        default = "0.1.30";
        description = "Nanos release version";
      };

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
      chown -R nanos:nanos /var/lib/nanos
      rm -f "/var/lib/nanos/.ops/packages"
      ln -s "${mkPackagesDir}" "/var/lib/nanos/.ops/packages"
      rm -f "/var/lib/nanos/.ops/${cfg.version}"
      ln -s "${mkReleaseDir}" "/var/lib/nanos/.ops/${cfg.version}"
    '';

  } (setAttrByPath ["systemd" "services"] services));
}
