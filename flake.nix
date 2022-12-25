{
  description = "Publish BME680 sensor data to home-assistant via MQTT";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({self, ...}: {
      perSystem = { pkgs, ... }: {
        packages.bme680-mqtt = pkgs.python3.pkgs.callPackage ./default.nix {
          src = self;
        };
        defaultPackage = self.packages.bme680-mqtt;
      };
      flake.nixosModules.bme680-mqtt = import ./module.nix;
    });
}
