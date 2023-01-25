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
    (bme680.override {
      smbus-cffi = smbus-cffi.overrideAttrs (old: {
        # bug in fetchpatch?
        preBuild = ''
          touch smbus/py.typed
        '';
        patches = old.patches ++ [
          # https://github.com/bivab/smbus-cffi/pull/25
          (fetchpatch {
            url = "https://github.com/bivab/smbus-cffi/commit/9e72d80e4d8362c966dc65270f43a6ab9e703578.patch";
            sha256 = "sha256-Tsq+6PIw/3o/GXo73Nza7USws6UAeG2u4slRB0KQR6U=";
          })
        ];
      });
    })
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
    ruff --check bme680_mqtt
    echo -e "\x1b[32m## run mypy\x1b[0m"
    mypy bme680_mqtt
  '';
}
