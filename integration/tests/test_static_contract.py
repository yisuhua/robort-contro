"""Offline-only contract tests; not ROS, Gazebo, MATLAB, CAD or dynamics tests."""
import math
import re
import unittest
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PKG = ROOT / 'integration/ros2_ws/src/industrial_robot_integration'
XACRO = PKG / 'urdf/robot.urdf.xacro'
MATLAB = ROOT / 'matlab/robot_model/build_robot.m'
SIZES = {'d1': .320, 'a1': .080, 'L2': .350, 'L3': .340, 'L4': .130}
AXES = ['0 0 1', '0 1 0', '0 1 0', '1 0 0', '0 1 0', '1 0 0']
OFFSETS = ['0 0 0', '${a1} 0 ${d1}', '${L2} 0 0',
           '${L3} 0 0', '0 0 0', '0 0 0']


class Contract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.xml = ET.parse(XACRO).getroot()
        cls.matlab = MATLAB.read_text(encoding='utf-8')

    def test_matlab_constants_unchanged(self):
        for symbol, expected in SIZES.items():
            match = re.search(r'^\s*' + symbol + r'\s*=\s*([0-9.]+)\s*;', self.matlab, re.M)
            self.assertIsNotNone(match, symbol)
            self.assertAlmostEqual(float(match.group(1)), expected, places=12)
        self.assertIn("rigidBodyTree('DataFormat','column')", self.matlab)

    def test_xacro_matches_stage2_geometry(self):
        ns = '{http://www.ros.org/wiki/xacro}'
        props = {p.attrib['name']: float(p.attrib['value'])
                 for p in self.xml.findall(ns + 'property')
                 if p.attrib['name'] in SIZES}
        self.assertEqual(props, SIZES)
        joints = [next(j for j in self.xml.findall('joint') if j.attrib['name'] == 'joint' + str(i))
                  for i in range(1, 7)]
        self.assertEqual([j.find('axis').attrib['xyz'] for j in joints], AXES)
        self.assertEqual([j.find('origin').attrib['xyz'] for j in joints], OFFSETS)
        self.assertEqual([j.find('origin').attrib['rpy'] for j in joints], ['0 0 0'] * 6)
        self.assertEqual([j.attrib['type'] for j in joints], ['revolute'] + ['continuous'] * 5)
        tool = next(j for j in self.xml.findall('joint') if j.attrib['name'] == 'tool_fixed')
        self.assertEqual(tool.find('origin').attrib['xyz'], '${L4} 0 0')
        self.assertAlmostEqual(float(next(p.attrib['value'] for p in self.xml.findall(ns+'property')
                                          if p.attrib['name']=='j1limit')), math.radians(170), places=12)

    def test_control_and_source_ownership(self):
        ns = '{http://www.ros.org/wiki/xacro}'
        invokes = self.xml.findall('.//' + ns + 'demo_joint_interface')
        self.assertEqual([v.attrib['name'] for v in invokes],
                         ['joint' + str(i) for i in range(1,7)])
        control = self.xml.find('ros2_control')
        # ros2_control exists only inside demo_mode if, not in base kinematic mode.
        self.assertIsNone(control)
        source = XACRO.read_text(encoding='utf-8')
        self.assertIn('<xacro:if value="$(arg demo_mode)">',source)
        self.assertIn('gz_ros2_control/GazeboSimSystem', source)
        self.assertIn('joint_state_broadcaster', (PKG/'config/controllers.yaml').read_text())
        self.assertIn('allow_partial_joints_goal: false', (PKG/'config/controllers.yaml').read_text())
        self.assertIn("topic', 'robot_description'", (PKG/'launch/demo.launch.py').read_text())
        self.assertNotIn('gazebo_ros2_control/GazeboSystem', source)

    def test_xml_resources(self):
        self.assertEqual(ET.parse(PKG/'package.xml').getroot().attrib['format'], '3')
        self.assertEqual(ET.parse(PKG/'worlds/empty.sdf').getroot().attrib['version'], '1.9')

    def test_matlab_interface_preserves_rigidbody(self):
        txt = (ROOT/'integration/matlab/ros2_roundtrip_demo.m').read_text()
        self.assertIn("strcmp(robot.DataFormat,'column')",txt)
        self.assertIn('0.03',txt)
        self.assertIn("'/joint_states'",txt)
        self.assertIn("'/joint_trajectory_controller/joint_trajectory'",txt)


if __name__ == '__main__':
    unittest.main()
