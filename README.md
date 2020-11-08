# bme680-mqtt
Publish BME680 sensor data to home-assistant via MQTT

## INSTALLATION

You an install the project with

```console
$ pip install git+https://github.com/Mic92/bme680-mqtt
```

This will also install the following, required python libraries:

- [paho-mqtt](https://pypi.org/project/paho-mqtt)
- [bme680](https://github.com/pimoroni/bme680-python/tree/master/library)


## USAGE

```console
$ bme680-mqtt --help
usage: bme680-mqtt [-h] [--name NAME] [--topic-prefix TOPIC_PREFIX] [--i2c-address I2C_ADDRESS] [--i2c-bus I2C_BUS] url

publish bme680 sensor to home-assistant via mqtt

positional arguments:
  url                   mqtt broker to write to, format: [mqtt][s]://[username][:password]@host.domain[:port]

optional arguments:
  -h, --help            show this help message and exit
  --name NAME           Name prefix used when publishing (default BME680)
  --topic-prefix TOPIC_PREFIX
                        Topic prefix used when publishing (default: homeassistant/sensor/bme680)
  --i2c-address I2C_ADDRESS
                        I2C address of the bme680 sensor (default: 0x76)
  --i2c-bus I2C_BUS     I2C bus of the bme680 sensor (default: 1)
```

Example: Local mqtt broker without authentication

```console
$ bme680-mqtt mqtt://localhost:1886
```

Example: Remote broker with TLS and authentication

```console
$ bme680-mqtt mqtts://username:password@mqtt.example.com:8886
```
