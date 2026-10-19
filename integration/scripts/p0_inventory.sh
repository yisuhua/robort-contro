#!/usr/bin/env bash
# Read-only: run only in an explicit ROS 2/Gazebo host; does not install software.
set -uo pipefail
OUT="${1:-./p0_inventory.txt}"
mkdir -p "$(dirname "$OUT")"
{
  echo "UTC: $(date -u +%FT%TZ)"
  echo "uname: $(uname -a)"
  echo "ROS_DISTRO: ${ROS_DISTRO:-UNSET}"
  echo "RMW_IMPLEMENTATION: ${RMW_IMPLEMENTATION:-UNSET}"
  echo "ROS_DOMAIN_ID: ${ROS_DOMAIN_ID:-UNSET}"
  for cmd in ros2 gz ign colcon xacro; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "$cmd: $(command -v "$cmd")"
    else
      echo "$cmd: MISSING"
    fi
  done
  if command -v gz >/dev/null 2>&1; then
    gz sim --versions 2>&1 || true
  fi
  if command -v ros2 >/dev/null 2>&1; then
    for pkg in ros_gz_sim ros_gz_bridge gz_ros2_control robot_state_publisher \
               controller_manager joint_trajectory_controller joint_state_broadcaster xacro; do
      printf 'package %s: ' "$pkg"
      ros2 pkg prefix "$pkg" 2>/dev/null || echo MISSING
    done
    echo 'ROS nodes:'
    timeout 5 ros2 node list 2>&1 || true
  fi
} | tee "$OUT"
echo "Wrote: $OUT"
