{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nanos;
in
{
  options = {
    services.nanos = {
      enable = mkEnableOption "Enable NanoVMS";

      vms = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            name = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            config = mkOption {
              type = types.submodule {
                options = {
                };
              };
              description = "VM config, will be passed as JSON to OPS";
              default = {};
            };
          };
        });
        description = ''
          Virtual machine configuration.
        '';
        default = {};
      };
    };
  };

  config = mkIf cfg.enable {

  };
}
