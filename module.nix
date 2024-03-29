  {
    config,
    pkgs,
    lib,
    ...
  }: let
    cfg = config.services.bme680-mqtt;
  in {
    options = {
      services.bme680-mqtt = {
        enable = lib.mkEnableOption "bme680-mqtt";
        package = lib.mkOption {
          type = lib.types.path;
          description = lib.mdDoc "package to use in this module";
        };
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
      systemd.services.bme680-mqtt =
        {
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            DynamicUser = true;
            User = "bme680-mqtt";
            SupplementaryGroups = ["i2c"];
            RuntimeDirectory = "bme680-mqtt";
            PermissionsStartOnly = "true";
            Restart = "on-failure";
            ExecStart = ''
              ${cfg.package}/bin/bme680-mqtt --quiet \
                --name "${cfg.mqtt.name}" \
                --topic-prefix "${cfg.mqtt.topicPrefix}" \
                --i2c-address "${toString cfg.i2c.address}" \
                --i2c-bus "${toString cfg.i2c.bus}" \
                ${lib.optionalString (cfg.mqtt.passwordFile != null) "--password-file /run/bme680-mqtt/password"} \
                ${cfg.mqtt.url}
            '';
          };
        }
        // lib.optionalAttrs (cfg.mqtt.passwordFile != null) {
          preStart = ''
            install -o bme680-mqtt -m400 ${cfg.mqtt.passwordFile} /run/bme680-mqtt/password
          '';
        };
      users.groups.i2c = {};
      systemd.tmpfiles.rules = [
        "c /dev/i2c-${toString cfg.i2c.bus} 0660 root i2c - 89:${toString cfg.i2c.bus}"
      ];
    };
  }
