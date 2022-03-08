{ pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixpkgs-unstable.tar.gz") {}
, python3 ? pkgs.python3
, mypy ? pkgs.mypy
, glibcLocales ? pkgs.glibcLocales
, buildPythonApplication ? python3.pkgs.buildPythonApplication
, black ? python3.pkgs.black
, flake8 ? python3.pkgs.flake8
, bme680 ? python3.pkgs.bme680
, smbus-cffi ? python3.pkgs.smbus-cffi
, paho-mqtt ? python3.pkgs.paho-mqtt
, src ? ./.
}:

let
  smbus-cffi' = smbus-cffi.overrideAttrs (old: {
    patches = old.patches ++ [
      # https://github.com/bivab/smbus-cffi/pull/25
      (pkgs.fetchpatch {
        url = "https://github.com/bivab/smbus-cffi/commit/4a23b92803f0b93196d52aff7dbdc394184cb774.patch";
        sha256 = "sha256-Sk51OlAB6c8ufP+TAvGroIVdwcqDo4dVdRPKweD6u24=";
      })
    ];
  });
in buildPythonApplication rec {
  name = "bme680-mqtt";
  inherit src;
  propagatedBuildInputs = [
    (bme680.override {
      smbus-cffi = smbus-cffi';
    })
    paho-mqtt
  ];
  checkInputs = [ 
    mypy
    glibcLocales
    black
    flake8
  ];
  checkPhase = ''
    echo -e "\x1b[32m## run black\x1b[0m"
    LC_ALL=en_US.utf-8 black --check .
    echo -e "\x1b[32m## run flake8\x1b[0m"
    flake8 bme680_mqtt
    echo -e "\x1b[32m## run mypy\x1b[0m"
    mypy bme680_mqtt
  '';
}
