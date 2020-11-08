{
  description = "Publish BME680 sensor data to home-assistant via MQTT";

  inputs.utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";

  outputs = { self, nixpkgs, utils }:
    (utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in rec {
        packages.bme680-mqtt = pkgs.python3.pkgs.callPackage ./default.nix {
          src = self;
        };
        defaultPackage = packages.bme680-mqtt;
      })) // {
        nixosModules.bme680-mqtt = { config, pkgs, lib, ... }: let
          cfg = config.services.bme680-mqtt;
        in {
          options = {
            services.bme680-mqtt = {
              enable = lib.mkEnableOption "bme680-mqtt";
              i2c.bus = lib.mkOption {
                type = lib.types.int;
                default = 1;
                example = 4;
                description = ''
                  I2C bus number where the bme680 is connected to.
                  Hint: last digit of device i.e. 1 for /dev/i2c-1
                '';
              };
              i2c.address = lib.mkOption {
                type = lib.types.str;
                default = "0x76";
                example = "0x77";
                description = ''
                  I2C address where the bme680 is connected to.
                '';
              };
              mqtt.name = lib.mkOption {
                type = lib.types.str;
                default = "bme680";
                description = ''
                  Name used in home-assistant
                '';
              };
              mqtt.topicPrefix = lib.mkOption {
                type = lib.types.str;
                default = "homeassistant/sensor/bme680";
                description = ''
                  MQTT topic prefix
                '';
              };
              mqtt.url = lib.mkOption {
                type = lib.types.str;
                example = "mqtt://localhost";
                description = ''
                  MQTT broker url, see https://github.com/Mic92/bme680-mqtt#usage for example
                '';
              };
              mqtt.passwordFile = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                example = "/var/lib/mqtt-password";
                description = ''
                  Password file used for authentication against MQTT broker.
                  If not set, it might use the password specified in mqtt-url.
                '';
              };
            };
          };
          config = {
            systemd.services.bme680-mqtt = {
              serviceConfig = {
                DynamicUser = true;
                User = "bme680-mqtt";
                SupplementaryGroups = [ "i2c" ];
                RuntimeDirectory = "bme680-mqtt";
                PermissionsStartOnly = "true";
                ExecStart = ''
                  ${self.defaultPackage.${pkgs.system}}/bin/bme680-mqtt  \
                    --name "${cfg.mqtt.name}" \
                    --topic-prefix "${cfg.mqtt.topicPrefix}" \
                    --i2c-address "${toString cfg.i2c.address}" \
                    --i2c-bus "${toString cfg.i2c.bus}" \
                    ${lib.optionalString (cfg.mqtt.passwordFile != null) "--password-file /run/bme680-mqtt/password"} \
                    ${cfg.mqtt.url}
                '';
              };
            } // lib.optionalAttrs (cfg.mqtt.passwordFile != null) {
              preStart = ''
                install -o bme680-mqtt -m400 ${cfg.mqtt.passwordFile} /run/bme680-mqtt/password
              '';
            };
            users.groups.i2c = {};
            systemd.tmpfiles.rules = [
              "c /dev/i2c-${toString cfg.i2c.bus} 0660 root i2c - 89:${toString cfg.i2c.bus}"
            ];
          };
        };
      };
}
