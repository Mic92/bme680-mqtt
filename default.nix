{ pkgs ? import <nixpkgs> {}
, pythonPackages ? pkgs.python3.pkgs
}:

pythonPackages.buildPythonApplication rec {
  name = "bme680-mqtt";
  src = ./.;
  propagatedBuildInputs = [
    pythonPackages.bme680
    pythonPackages.paho-mqtt
  ];
  checkInputs = [ 
    pkgs.mypy 
    pkgs.glibcLocales
    pythonPackages.black 
    pythonPackages.flake8 
  ];
  MYPYPATH = "${pythonPackages.bme680}/${pythonPackages.python.sitePackages}:" +
    "${pythonPackages.smbus-cffi}/${pythonPackages.python.sitePackages}:";
  checkPhase = ''
    echo -e "\x1b[32m## run black\x1b[0m"
    LC_ALL=en_US.utf-8 black --check .
    echo -e "\x1b[32m## run flake8\x1b[0m"
    flake8 bme680_mqtt
    echo -e "\x1b[32m## run mypy\x1b[0m"
    mypy bme680_mqtt
  '';
}
