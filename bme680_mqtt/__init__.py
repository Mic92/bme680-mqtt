"""Support for BME680 Sensor over SMBus."""
import logging
import threading
import time
import json
import uuid
import argparse
from time import monotonic, sleep
from typing import List, Optional
import paho.mqtt.client as mqtt
from urllib.parse import urlparse
from dataclasses import dataclass

import bme680  # pylint: disable=import-error
from smbus import SMBus  # pylint: disable=import-error

_LOGGER = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)


DEFAULT_OVERSAMPLING_TEMP = 8  # Temperature oversampling x 8
DEFAULT_OVERSAMPLING_PRES = 4  # Pressure oversampling x 4
DEFAULT_OVERSAMPLING_HUM = 2  # Humidity oversampling x 2
DEFAULT_FILTER_SIZE = 3  # IIR Filter Size
DEFAULT_GAS_HEATER_TEMP = 320  # Temperature in celsius 200 - 400
DEFAULT_GAS_HEATER_DURATION = 150  # Heater duration in ms 1 - 4032
DEFAULT_AQ_BURN_IN_TIME = 300  # 300 second burn in time for AQ gas measurement
DEFAULT_AQ_HUM_BASELINE = 40  # 40%, an optimal indoor humidity.
DEFAULT_AQ_HUM_WEIGHTING = 25  # 25% Weighting of humidity to gas in AQ score
DEFAULT_TEMP_OFFSET = 0  # No calibration out of the box.


@dataclass
class SensorType:
    name: str
    unit: str
    device_class: Optional[str]


SENSOR_TEMP = "temperature"
SENSOR_HUMID = "humidity"
SENSOR_PRESS = "pressure"
SENSOR_AQ = "airquality"

SENSOR_TYPES = {
    SENSOR_TEMP: SensorType("Temperature", "C", "temperature"),
    SENSOR_HUMID: SensorType("Humidity", "%", "humidity"),
    SENSOR_PRESS: SensorType("Pressure", "mb", "pressure"),
    SENSOR_AQ: SensorType("Air Quality", "%", None),
}
DEFAULT_MONITORED = [SENSOR_TEMP, SENSOR_HUMID, SENSOR_PRESS, SENSOR_AQ]
OVERSAMPLING_VALUES = {0, 1, 2, 4, 8, 16}
FILTER_VALUES = {0, 1, 3, 7, 15, 31, 63, 127}


@dataclass
class Options:
    name: str
    topic_prefix: str
    url: str
    password_file: Optional[str]
    i2c_address: int
    i2c_bus: int


class BME680Handler:
    """BME680 sensor working in i2C bus."""

    class SensorData:
        """Sensor data representation."""

        def __init__(self) -> None:
            """Initialize the sensor data object."""
            self.temperature: float = 0
            self.humidity: float = 0
            self.pressure: float = 0
            self.gas_resistance: int = 0
            self.air_quality: Optional[float] = None

    def __init__(
        self,
        sensor: bme680.BME680,
        burn_in_time: int = 300,
        hum_baseline: int = 40,
        hum_weighting: int = 25,
    ) -> None:
        """Initialize the sensor handler."""
        self.sensor_data = BME680Handler.SensorData()
        self._sensor = sensor
        self._hum_baseline = hum_baseline
        self._hum_weighting = hum_weighting
        self._gas_baseline: float = 0

        threading.Thread(
            target=self._run_gas_sensor,
            kwargs={"burn_in_time": burn_in_time},
            name="BME680Handler_run_gas_sensor",
        ).start()
        self.update(first_read=True)

    def _run_gas_sensor(self, burn_in_time: int) -> None:
        """Calibrate the Air Quality Gas Baseline."""
        # Pause to allow initial data read for device validation.
        sleep(1)

        start_time = monotonic()
        curr_time = monotonic()
        burn_in_data: List[float] = []

        _LOGGER.info(
            "Beginning %d second gas sensor burn in for Air Quality", burn_in_time
        )
        while curr_time - start_time < burn_in_time:
            curr_time = monotonic()
            if self._sensor.get_sensor_data() and self._sensor.data.heat_stable:
                gas_resistance = self._sensor.data.gas_resistance
                burn_in_data.append(gas_resistance)
                self.sensor_data.gas_resistance = gas_resistance
                _LOGGER.debug(
                    "AQ Gas Resistance Baseline reading %2f Ohms", gas_resistance
                )
                sleep(1)

        _LOGGER.debug(
            "AQ Gas Resistance Burn In Data (Size: %d): \n\t%s",
            len(burn_in_data),
            burn_in_data,
        )
        self._gas_baseline = sum(burn_in_data[-50:]) / 50.0
        _LOGGER.info("Completed gas sensor burn in for Air Quality")
        _LOGGER.info("AQ Gas Resistance Baseline: %f", self._gas_baseline)
        while True:
            if self._sensor.get_sensor_data() and self._sensor.data.heat_stable:
                self.sensor_data.gas_resistance = self._sensor.data.gas_resistance
                self.sensor_data.air_quality = self._calculate_aq_score()
                sleep(1)

    def update(self, first_read: bool = False) -> "BME680Handler.SensorData":
        """Read sensor data."""
        if first_read:
            # Attempt first read, it almost always fails first attempt
            self._sensor.get_sensor_data()
        if self._sensor.get_sensor_data():
            self.sensor_data.temperature = self._sensor.data.temperature
            self.sensor_data.humidity = self._sensor.data.humidity
            self.sensor_data.pressure = self._sensor.data.pressure
        return self.sensor_data

    def _calculate_aq_score(self) -> float:
        """Calculate the Air Quality Score."""
        hum_baseline = self._hum_baseline
        hum_weighting = self._hum_weighting
        gas_baseline = self._gas_baseline

        gas_resistance = self.sensor_data.gas_resistance
        gas_offset = gas_baseline - gas_resistance

        hum = self.sensor_data.humidity
        hum_offset = hum - hum_baseline

        # Calculate hum_score as the distance from the hum_baseline.
        if hum_offset > 0:
            hum_score = (
                (100 - hum_baseline - hum_offset) / (100 - hum_baseline) * hum_weighting
            )
        else:
            hum_score = (hum_baseline + hum_offset) / hum_baseline * hum_weighting

        # Calculate gas_score as the distance from the gas_baseline.
        if gas_offset > 0:
            gas_score = (gas_resistance / gas_baseline) * (100 - hum_weighting)
        else:
            gas_score = 100 - hum_weighting

        # Calculate air quality score.
        return hum_score + gas_score


def _setup_bme680(options: Options) -> Optional[BME680Handler]:
    """Set up and configure the BME680 sensor."""

    sensor_handler = None
    sensor = None
    try:
        # pylint: disable=no-member
        bus = SMBus(options.i2c_bus)
        sensor = bme680.BME680(options.i2c_address, bus)

        # Configure Oversampling
        os_lookup = {
            0: bme680.OS_NONE,
            1: bme680.OS_1X,
            2: bme680.OS_2X,
            4: bme680.OS_4X,
            8: bme680.OS_8X,
            16: bme680.OS_16X,
        }

        sensor.set_temperature_oversample(os_lookup[DEFAULT_OVERSAMPLING_TEMP])
        sensor.set_temp_offset(DEFAULT_TEMP_OFFSET)
        sensor.set_humidity_oversample(os_lookup[DEFAULT_OVERSAMPLING_HUM])
        sensor.set_pressure_oversample(os_lookup[DEFAULT_OVERSAMPLING_PRES])

        # Configure IIR Filter
        filter_lookup = {
            0: bme680.FILTER_SIZE_0,
            1: bme680.FILTER_SIZE_1,
            3: bme680.FILTER_SIZE_3,
            7: bme680.FILTER_SIZE_7,
            15: bme680.FILTER_SIZE_15,
            31: bme680.FILTER_SIZE_31,
            63: bme680.FILTER_SIZE_63,
            127: bme680.FILTER_SIZE_127,
        }
        sensor.set_filter(filter_lookup[DEFAULT_FILTER_SIZE])

        sensor.set_gas_status(bme680.ENABLE_GAS_MEAS)
        sensor.set_gas_heater_duration(DEFAULT_GAS_HEATER_DURATION)
        sensor.set_gas_heater_temperature(DEFAULT_GAS_HEATER_TEMP)
        sensor.select_gas_heater_profile(0)
    except (RuntimeError, OSError):
        _LOGGER.error("BME680 sensor not detected at 0x%02x", options.i2c_address)
        return None

    sensor_handler = BME680Handler(
        sensor,
        DEFAULT_AQ_BURN_IN_TIME,
        DEFAULT_AQ_HUM_BASELINE,
        DEFAULT_AQ_HUM_WEIGHTING,
    )
    sleep(0.5)  # Wait for device to stabilize
    if not sensor_handler.sensor_data.temperature:
        _LOGGER.error("BME680 sensor failed to Initialize")
        return None

    return sensor_handler


def _setup_mqtt(url: str, passwort_file: Optional[str]) -> mqtt.Client:
    client_id = mqtt.base62(uuid.uuid4().int, padding=22)
    mqttc = mqtt.Client(client_id)
    mqttc.enable_logger(_LOGGER)
    parsed = urlparse(url)

    if parsed.scheme == "mqtts":
        mqttc.tls_set()
    port = parsed.port or 1883
    password = parsed.password
    if passwort_file:
        with open(passwort_file) as f:
            password = f.read()

    if parsed.username:
        mqttc.username_pw_set(parsed.username, password)
    _LOGGER.info(f"connect to {parsed.hostname}:{parsed.port}")
    mqttc.connect(parsed.hostname, port=port, keepalive=60)
    mqttc.loop_start()
    return mqttc


def publish_sensor(
    mqttc: mqtt.Client, sensor_type: SensorType, options: Options
) -> None:
    data = dict(
        name=f"{options.name} {sensor_type.name}",
        unit_of_measurement=sensor_type.unit,
        state_topic="{options.topic_prefix}/state",
        value_template="{{ value_json.%s }}" % sensor_type,
    )
    if sensor_type.device_class:
        data["device_class"] = sensor_type.device_class
    config = json.dumps(data)
    mqttc.publish(f"{options.topic_prefix}-{sensor_type}/config", config, retain=True)


def publish_update(mqttc: mqtt.Client, sensor: BME680Handler, options: Options) -> None:
    data = sensor.update()
    state = {
        SENSOR_TEMP: round(data.temperature, 1),
        SENSOR_HUMID: round(data.humidity, 1),
        SENSOR_PRESS: round(data.pressure, 1),
        SENSOR_AQ: round(data.air_quality, 1) if data.air_quality else None,
    }
    mqttc.publish("{options.topic_prefix}/state", json.dumps(state))
    _LOGGER.info(f"state: {state}")


def parse_args() -> Options:
    parser = argparse.ArgumentParser(
        description="publish bme680 sensor to home-assistant via mqtt"
    )
    help = "mqtt broker to write to, format: [mqtt][s]://[username][:password]@host.domain[:port]"
    parser.add_argument("url", help=help, default="mqtt://localhost")
    parser.add_argument(
        "--name",
        help="Name prefix used when publishing (default BME680)",
        default="BME680",
    )
    parser.add_argument(
        "--topic-prefix",
        help="Topic prefix used when publishing (default: homeassistant/sensor/bme680)",
        default="homeassistant/sensor/bme680",
    )
    parser.add_argument(
        "--i2c-address",
        help="I2C address of the bme680 sensor (default: 0x76)",
        default=0x76,
        type=int,
    )
    parser.add_argument(
        "--i2c-bus",
        help="I2C bus of the bme680 sensor (default: 1)",
        default=1,
        type=int,
    )
    parser.add_argument(
        "--password-file",
        help="File to read password from (default: none)",
        default=None,
    )
    args = parser.parse_args()
    return Options(
        name=args.name,
        topic_prefix=args.topic_prefix,
        url=args.url,
        i2c_address=args.i2c_address,
        i2c_bus=args.i2c_bus,
        password_file=args.password_file
    )


def main() -> None:
    options = parse_args()
    sensor = _setup_bme680(options)
    if sensor is None:
        return
    mqttc = _setup_mqtt(options.url, options.password_file)
    for sensor_type in DEFAULT_MONITORED:
        publish_sensor(mqttc, SENSOR_TYPES[sensor_type], options)

    try:
        while True:
            publish_update(mqttc, sensor, options)
            time.sleep(10)
    finally:
        mqttc.loop_stop()


if __name__ == "__main__":
    main()
