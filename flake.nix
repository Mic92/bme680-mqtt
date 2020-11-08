{
  description = "Publish BME680 sensor data to home-assistant via MQTT";

  inputs.utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:Mic92/nixpkgs/bme680";

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachSystem utils.lib.allSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in rec {
        packages.bme680-mqtt = pkgs.python3.pkgs.callPackage ./default.nix {
          src = self;
        };
        defaultPackage = packages.bme680-mqtt;
      });
}
