{ fetchpatch
, python3
, mypy
, glibcLocales
, buildPythonApplication
, black
, ruff
, bme680
, smbus-cffi
, paho-mqtt
, src
}:

buildPythonApplication rec {
  name = "bme680-mqtt";
  inherit src;
  propagatedBuildInputs = [
    bme680
    paho-mqtt
  ];
  nativeCheckInputs = [
    mypy
    black
    ruff
  ];

  checkPhase = ''
    echo -e "\x1b[32m## run black\x1b[0m"
    black --check .
    echo -e "\x1b[32m## run ruff\x1b[0m"
    ruff .
    echo -e "\x1b[32m## run mypy\x1b[0m"
    mypy bme680_mqtt
  '';
}
