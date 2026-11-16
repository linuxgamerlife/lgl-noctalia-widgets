#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 LinuxGamerLife

"""Unit tests for the evdev helper (no /dev/input access required)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN_DIR = Path(__file__).resolve().parents[3] / "kbm-overlay"
sys.path.insert(0, str(PLUGIN_DIR / "code"))

import kbm_daemon as daemon  # noqa: E402

class KeyNameTests(unittest.TestCase):
    def test_common_keys(self) -> None:
        self.assertEqual(daemon.key_name(30), "KEY_A")
        self.assertEqual(daemon.key_name(57), "KEY_SPACE")
        self.assertEqual(daemon.key_name(daemon.BTN_LEFT), "BTN_LEFT")
        self.assertEqual(daemon.key_name(daemon.BTN_SIDE), "BTN_SIDE")
        self.assertEqual(daemon.key_name(9999), "KEY_9999")

    def test_mouse_order(self) -> None:
        self.assertEqual(daemon.MOUSE_BUTTON_ORDER[0], "BTN_LEFT")
        self.assertIn("BTN_SIDE", daemon.MOUSE_BUTTON_ORDER)

class CursorTests(unittest.TestCase):
    def test_parse_cursor(self) -> None:
        self.assertEqual(daemon.parse_cursor_position("x:1822 y:1632 screen:0 window:{}"), (1822, 1632))
        self.assertEqual(daemon.parse_cursor_position("x:-10 y:20"), (-10, 20))
        self.assertIsNone(daemon.parse_cursor_position("no cursor here"))


class InputStateTests(unittest.TestCase):
    def test_press_release_and_wheel(self) -> None:
        state = daemon.InputState()
        state.handle(daemon.EV_KEY, 30, 1)
        state.handle(daemon.EV_KEY, daemon.BTN_LEFT, 1)
        self.assertEqual(state.pressed, {"KEY_A", "BTN_LEFT"})
        self.assertTrue(state.dirty)

        state.handle(daemon.EV_KEY, 30, 2)
        self.assertEqual(state.pressed, {"KEY_A", "BTN_LEFT"})

        state.handle(daemon.EV_KEY, 30, 0)
        self.assertEqual(state.pressed, {"BTN_LEFT"})

        state.handle(daemon.EV_REL, daemon.REL_X, 5)
        state.handle(daemon.EV_REL, daemon.REL_Y, -3)
        self.assertEqual(state.move_x, 5)
        self.assertEqual(state.move_y, -3)
        self.assertGreater(state.move_at, 0)

        state.handle(daemon.EV_REL, daemon.REL_WHEEL, 2)
        state.handle(daemon.EV_REL, daemon.REL_WHEEL, -1)
        self.assertEqual(state.wheel_up, 2)
        self.assertEqual(state.wheel_down, 1)

        keyboard = [daemon.Device("/dev/input/event1", "Keyboard")]
        mouse = [daemon.Device("/dev/input/event2", "Mouse", buttons=["BTN_LEFT"])]
        snapshot = state.snapshot(keyboard, mouse)
        self.assertEqual(snapshot["type"], "state")
        self.assertEqual(snapshot["pressed"], ["BTN_LEFT"])
        self.assertEqual(snapshot["keyboard"]["name"], "Keyboard")
        self.assertEqual(snapshot["mouse"]["buttons"], ["BTN_LEFT"])
        self.assertEqual(snapshot["move_x"], 5)
        self.assertEqual(snapshot["move_y"], -3)
        self.assertEqual(snapshot["move_seq"], 1)
        self.assertFalse(state.dirty)

class SelectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.keyboard = daemon.Device(
            "/dev/input/event1", "Keyboard", vendor="1234", product="abcd",
            keyboard=True,
        )
        self.mouse = daemon.Device(
            "/dev/input/event2", "Mouse", vendor="5678", product="ef01",
            mouse=True, buttons=["BTN_LEFT"],
        )

    def test_first_available(self) -> None:
        chosen = daemon.choose([self.keyboard, self.mouse], "", "", "keyboard")
        self.assertEqual(chosen, [self.keyboard])

    def test_exact_path(self) -> None:
        other = daemon.Device("/dev/input/event9", "Other", keyboard=True)
        chosen = daemon.choose([self.keyboard, other], "", "/dev/input/event9", "keyboard")
        self.assertEqual(chosen, [other])

    def test_exact_name(self) -> None:
        other = daemon.Device("/dev/input/event9", "Other", keyboard=True)
        chosen = daemon.choose([self.keyboard, other], "Other", "", "keyboard")
        self.assertEqual(chosen, [other])

    def test_unreadable_selection_is_not_replaced(self) -> None:
        blocked = daemon.Device(
            "/dev/input/event8", "Blocked", keyboard=True, readable=False,
            error="permission",
        )
        chosen = daemon.choose([self.keyboard, blocked], "Blocked", "/dev/input/event8", "keyboard")
        self.assertEqual(chosen, [blocked])

    def test_missing_selection_does_not_fall_back(self) -> None:
        chosen = daemon.choose([self.keyboard], "Gone", "", "keyboard")
        self.assertEqual(chosen, [])

    def test_wildcard_returns_readable(self) -> None:
        blocked = daemon.Device(
            "/dev/input/event8", "Blocked", keyboard=True, readable=False,
        )
        chosen = daemon.choose([self.keyboard, blocked], "*", "", "keyboard")
        self.assertEqual(chosen, [self.keyboard])

class ConfigTests(unittest.TestCase):
    def test_load_config(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "devices.json"
            path.write_text(json.dumps({"keyboard": "Kbd", "mouse": "Mouse"}))
            self.assertEqual(daemon.load_config(str(path))["keyboard"], "Kbd")
            self.assertEqual(daemon.load_config(str(Path(directory) / "missing.json")), {})

    def test_event_struct(self) -> None:
        data = daemon.EVENT.pack(0, 0, daemon.EV_KEY, 30, 1)
        self.assertEqual(len(data), daemon.EVENT_SIZE)
        _, _, ev_type, code, value = daemon.EVENT.unpack(data)
        self.assertEqual((ev_type, code, value), (daemon.EV_KEY, 30, 1))

class UdevRuleTests(unittest.TestCase):
    def _run_rule(
        self,
        data: dict,
        existing: str | None = None,
        args: tuple[str, ...] = (),
    ) -> subprocess.CompletedProcess[str]:
        script = PLUGIN_DIR / "code" / "setup-input-permissions.sh"
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            config_dir = state / "noctalia-kwe" / "plugins" / "data" / "linuxgamerlife" / "kbm-overlay"
            config_dir.mkdir(parents=True)
            (config_dir / "devices.json").write_text(json.dumps(data))
            rule = state / "70-lgl-kbm-overlay.rules"
            if existing is not None:
                rule.write_text(existing)
            env = dict(os.environ)
            env["NOCTALIA_STATE_HOME"] = str(state)
            # Keep tests away from the host's real rule in /etc.
            env["KBM_UDEV_RULE"] = str(rule)
            return subprocess.run(
                ["bash", str(script), "--print", *args],
                capture_output=True,
                text=True,
                env=env,
                check=False,
            )

    def test_valid_rule_is_narrow(self) -> None:
        result = self._run_rule({
            "keyboard": "Keyboard",
            "keyboard_vendor": "1234",
            "keyboard_product": "abcd",
            "mouse": "Mouse",
            "mouse_vendor": "5678",
            "mouse_product": "ef01",
        })
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ATTRS{id/vendor}=="1234"', result.stdout)
        self.assertIn('ATTRS{id/product}=="ef01"', result.stdout)
        self.assertIn('KERNEL=="event*"', result.stdout)
        self.assertIn('TAG+="uaccess"', result.stdout)

    def test_injection_in_ids_is_rejected(self) -> None:
        result = self._run_rule({
            "keyboard": "Keyboard",
            "keyboard_vendor": "1234\", RUN+=\"/tmp/evil",
            "keyboard_product": "abcd",
            "mouse": "Mouse",
            "mouse_vendor": "5678",
            "mouse_product": "ef01",
        })
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid USB vendor/product", result.stderr)

    def test_missing_ids_are_rejected(self) -> None:
        result = self._run_rule({"keyboard": "Keyboard", "mouse": "Mouse"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid USB vendor/product", result.stderr)

    def test_existing_devices_are_kept(self) -> None:
        # A rule from an earlier picker run must not disable the old mouse when
        # the user switches devices.
        existing = (
            "# LGL KBM Overlay: 3434:d028\n"
            'SUBSYSTEM=="input", ATTRS{id/vendor}=="3434", ATTRS{id/product}=="d028", TAG+="uaccess"\n'
        )
        result = self._run_rule({
            "keyboard": "Keyboard",
            "keyboard_vendor": "1234",
            "keyboard_product": "abcd",
            "mouse": "Mouse",
            "mouse_vendor": "3434",
            "mouse_product": "d05a",
        }, existing=existing)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ATTRS{id/product}=="d028"', result.stdout)
        self.assertIn('ATTRS{id/product}=="d05a"', result.stdout)
        self.assertIn('KERNEL=="event*"', result.stdout)

    def test_reset_drops_devices_from_earlier_runs(self) -> None:
        existing = (
            'SUBSYSTEM=="input", ATTRS{id/vendor}=="3434", ATTRS{id/product}=="d028", TAG+="uaccess"\n'
        )
        result = self._run_rule({
            "keyboard": "Keyboard",
            "keyboard_vendor": "1234",
            "keyboard_product": "abcd",
            "mouse": "Mouse",
            "mouse_vendor": "3434",
            "mouse_product": "d05a",
        }, existing=existing, args=("--reset",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("d028", result.stdout)
        self.assertIn('ATTRS{id/product}=="d05a"', result.stdout)

    def test_unrelated_lines_are_preserved(self) -> None:
        existing = 'SUBSYSTEM=="usb", ATTR{idVendor}=="1234", MODE="0660"\n'
        result = self._run_rule({
            "keyboard": "Keyboard",
            "keyboard_vendor": "1234",
            "keyboard_product": "abcd",
            "mouse": "Mouse",
            "mouse_vendor": "5678",
            "mouse_product": "ef01",
        }, existing=existing)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('SUBSYSTEM=="usb"', result.stdout)


class UdevCoverageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.device = daemon.Device(
            "/dev/input/event12", "Keychron Keychron TurboLink 8K Mouse",
            vendor="3434", product="d05a", mouse=True, readable=False,
            error="permission",
        )

    def _message(self, rule: str | None) -> str:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "70-lgl-kbm-overlay.rules"
            if rule is not None:
                path.write_text(rule)
            return daemon.permission_message(self.device, rule_path=path)

    def test_missing_rule_points_at_the_helper(self) -> None:
        message = self._message(None)
        self.assertIn("No LGL KBM Overlay udev rule", message)
        self.assertIn("setup-input-permissions.sh", message)

    def test_rule_for_another_device_is_reported_as_stale(self) -> None:
        message = self._message(
            'SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="3434", '
            'ATTRS{id/product}=="d028", TAG+="uaccess"\n'
        )
        self.assertIn("does not cover", message)
        self.assertIn("3434:d05a", message)
        self.assertIn("replug", message)

    def test_covered_device_suggests_replugging(self) -> None:
        message = self._message(
            'SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="3434", '
            'ATTRS{id/product}=="d05a", TAG+="uaccess"\n'
        )
        self.assertIn("covers 3434:d05a", message)
        self.assertIn("replug", message)

    def test_uninspectable_rule_stays_generic(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            # A directory cannot be read as a rule file; the daemon must not
            # claim the rule is missing when it could not look at it.
            message = daemon.permission_message(self.device, rule_path=Path(directory))
        self.assertIn("Permission denied", message)

    def test_read_rule_pairs_ignores_unmanaged_lines(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "rule"
            path.write_text(
                'SUBSYSTEM=="usb", ATTR{idVendor}=="3434", MODE="0660"\n'
                'SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="3434", '
                'ATTRS{id/product}=="d05a", TAG+="uaccess"\n'
            )
            self.assertEqual(daemon.read_rule_pairs(path), {("3434", "d05a")})
            self.assertEqual(daemon.read_rule_pairs(Path(directory) / "missing"), set())

if __name__ == "__main__":
    unittest.main()
