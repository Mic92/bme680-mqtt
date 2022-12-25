{
  description = "Publish BME680 sensor data to home-assistant via MQTT";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({self, ...}: {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      perSystem = { self', pkgs, ... }: {
        packages.bme680-mqtt = pkgs.python3.pkgs.callPackage ./default.nix {
          src = self;
        };
        packages.default = self'.packages.bme680-mqtt;
      };
      flake.nixosModules.bme680-mqtt = { pkgs, ... }: {
        imports = [./module.nix];
        services.bme680-mqtt.package = self.packages.${pkgs.hostPlatform.system}.default;
      };
    });
}
