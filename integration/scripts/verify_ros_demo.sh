#!/usr/bin/env bash
# Run ONLY on an explicitly provisioned ROS 2 + Gazebo demo host, not hardware.
set -euo pipefail
OUT_DIR="${1:-./ros_demo_reports}"
mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$OUT_DIR/demo_verify_$STAMP.txt"
{
  date -u +%FT%TZ
  echo "ROS_DISTRO=${ROS_DISTRO:-UNKNOWN}"
  ros2 pkg prefix industrial_robot_integration
  ros2 control list_controllers
  ros2 topic type /clock
  ros2 topic type /joint_states
  ros2 topic type /joint_trajectory_controller/joint_trajectory
  timeout 15 ros2 topic echo /clock --once
  timeout 15 ros2 topic echo /joint_states --once
  ros2 run industrial_robot_integration feedback_probe --samples 10 --timeout 25
} 2>&1 | tee "$LOG"
echo "Saved: $LOG"
