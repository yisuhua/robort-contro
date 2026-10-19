"""Read-only ROS 2 joint-state inspection. NEVER sends actuator commands."""
import argparse
import json
import math
import time

NAMES = tuple('joint' + str(i) for i in range(1, 7))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--samples', type=int, default=10)
    parser.add_argument('--timeout', type=float, default=15.0)
    args = parser.parse_args()
    if args.samples < 2 or args.timeout <= 0:
        parser.error('samples >= 2 and timeout > 0 required')
    import rclpy
    from sensor_msgs.msg import JointState

    rclpy.init()
    node = rclpy.create_node('industrial_robot_feedback_probe')
    observed = []
    failures = []
    deadline = time.monotonic() + args.timeout
    previous_time = None

    def callback(msg):
        nonlocal previous_time
        names = list(msg.name)
        if len(set(names)) != len(names):
            failures.append('duplicate joint names')
            return
        if not set(NAMES).issubset(names) or len(msg.position) < len(names):
            failures.append('missing joint names or positions')
            return
        q = [float(msg.position[names.index(n)]) for n in NAMES]
        if any(not math.isfinite(value) for value in q):
            failures.append('non-finite joint position')
            return
        stamp = int(msg.header.stamp.sec) * 1000000000 + int(msg.header.stamp.nanosec)
        if stamp <= 0:
            failures.append('zero /clock timestamp')
            return
        if previous_time is not None and stamp < previous_time:
            failures.append('non-monotonic timestamp')
            return
        previous_time = stamp
        observed.append({'sim_time_ns': stamp, 'positions_rad': q})

    sub = node.create_subscription(JointState, '/joint_states', callback, 10)
    try:
        while len(observed) < args.samples and time.monotonic() < deadline:
            rclpy.spin_once(node, timeout_sec=0.2)
        result = {'status': 'PASS' if len(observed) >= args.samples and not failures else 'FAILED',
                  'samples': len(observed), 'joint_names': list(NAMES),
                  'errors': failures, 'last': observed[-1] if observed else None}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        if result['status'] != 'PASS':
            raise SystemExit(1)
    finally:
        node.destroy_subscription(sub)
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
