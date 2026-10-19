"""Demo-only ROS2 trajectory roundtrip; NEVER connect to real robot hardware."""
import json
import math
import time

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import JointState
from trajectory_msgs.msg import JointTrajectory, JointTrajectoryPoint

JOINTS = ['joint'+str(i) for i in range(1,7)]
TOPIC = '/joint_trajectory_controller/joint_trajectory'
TARGET_J1_RAD = .03  # Communication-only demonstration; J1 ±170 deg confirmed.


class Roundtrip(Node):
    def __init__(self):
        super().__init__('demo_command_probe')
        self.pub = self.create_publisher(JointTrajectory, TOPIC, 10)
        self.sub = self.create_subscription(JointState, '/joint_states', self.on_state, 10)
        self.current = None
        self.timestamps = []
        self.bad = None

    def on_state(self, msg):
        if len(set(msg.name)) != len(msg.name) or not set(JOINTS).issubset(msg.name):
            self.bad = 'Duplicate or missing joint names'
            return
        if len(msg.position) != len(msg.name):
            self.bad = 'JointState name-position length mismatch'
            return
        q = [float(msg.position[msg.name.index(name)]) for name in JOINTS]
        if any(not math.isfinite(x) for x in q):
            self.bad = 'Non-finite joint position'
            return
        stamp = msg.header.stamp.sec * 1000000000 + msg.header.stamp.nanosec
        if stamp <= 0 or (self.timestamps and stamp < self.timestamps[-1]):
            self.bad = 'Zero or reversed simulation timestamp'
            return
        self.timestamps.append(stamp)
        self.current = q

    def perform(self):
        deadline = time.monotonic() + 30.0
        while time.monotonic() < deadline:
            rclpy.spin_once(self, timeout_sec=.2)
            if self.bad:
                raise RuntimeError(self.bad)
            if self.current is not None and self.pub.get_subscription_count():
                break
        if self.current is None or not self.pub.get_subscription_count():
            raise RuntimeError('JointState feedback or trajectory controller unavailable')
        if max(abs(q) for q in self.current) >= .08:
            raise RuntimeError('Robot not at demo home; refusing motion')
        msg = JointTrajectory()
        msg.joint_names = JOINTS
        point = JointTrajectoryPoint()
        point.positions = [TARGET_J1_RAD, 0., 0., 0., 0., 0.]
        point.time_from_start.sec = 4
        msg.points = [point]
        self.pub.publish(msg)
        deadline = time.monotonic() + 12.0
        while time.monotonic() < deadline:
            rclpy.spin_once(self, timeout_sec=.2)
            if self.bad:
                raise RuntimeError(self.bad)
            if self.current is not None and abs(self.current[0]-TARGET_J1_RAD) < .01:
                if max(abs(q) for q in self.current[1:]) > .02:
                    raise RuntimeError('Non-commanded joint unexpectedly moved')
                print(json.dumps({'status':'DEMO_ROUNDTRIP_OBSERVED',
                                  'joint_positions_rad':self.current,
                                  'observed_samples':len(self.timestamps)}))
                return
        raise RuntimeError('Command did not produce bounded feedback before timeout')


def main():
    rclpy.init()
    node = Roundtrip()
    try:
        node.perform()
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
