{ pkgs ? import (fetchTarball "https://github.com/Mic92/nixpkgs/archive/bme680.tar.gz") {}
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

buildPythonApplication rec {
  name = "bme680-mqtt";
  inherit src;
  propagatedBuildInputs = [
    bme680
    paho-mqtt
  ];
  checkInputs = [ 
    mypy
    glibcLocales
    black
    flake8
  ];
  MYPYPATH = "${bme680}/${python3.sitePackages}:${smbus-cffi}/${python3.sitePackages}";
  checkPhase = ''
    echo -e "\x1b[32m## run black\x1b[0m"
    LC_ALL=en_US.utf-8 black --check .
    echo -e "\x1b[32m## run flake8\x1b[0m"
    flake8 bme680_mqtt
    echo -e "\x1b[32m## run mypy\x1b[0m"
    mypy bme680_mqtt
  '';
}
