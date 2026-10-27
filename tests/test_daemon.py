#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


DAEMON_PATH = Path(__file__).resolve().parents[1] / "dualsense/code/ds_battery_daemon.py"
SPEC = importlib.util.spec_from_file_location("ds_battery_daemon", DAEMON_PATH)
daemon = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(daemon)


class Ds4uConfigTests(unittest.TestCase):
    def test_lightbar_uses_ds4u_brightness_scaling(self):
        with tempfile.TemporaryDirectory() as tmp:
            config_dir = Path(tmp) / "ds4u"
            profiles = config_dir / "profiles"
            profiles.mkdir(parents=True)
            (config_dir / "settings.json").write_text(json.dumps({"profile": "Default"}))
            (profiles / "Default.json").write_text(json.dumps({
                "name": "Default",
                "lightbar_r": 1.0,
                "lightbar_g": 0.5,
                "lightbar_b": 0.0,
                "lightbar_brightness": 128.0,
            }))

            old_dir = daemon.DS4U_CONFIG_DIR
            daemon.DS4U_CONFIG_DIR = str(config_dir)
            try:
                state = daemon.read_ds4u_config()
            finally:
                daemon.DS4U_CONFIG_DIR = old_dir

            # Matches ds4u's integer conversion and channel scaling:
            # (255 * 128) / 255 = 128; (127 * 128) / 255 = 63.
            self.assertEqual(state["lightbar_color"], "#803f00")


if __name__ == "__main__":
    unittest.main()
